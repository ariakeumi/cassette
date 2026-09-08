// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftSonic
import SwiftUI

struct PlaylistDetailMacOS: View {
    let playlistId: String
    let name: String
    let coverArtId: String?
    var showBackButton: Bool = true

    init(playlistId: String, name: String, coverArtId: String? = nil, showBackButton: Bool = true) {
        self.playlistId = playlistId
        self.name = name
        self.coverArtId = coverArtId
        self.showBackButton = showBackButton
    }

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PlaylistDetailViewModel?
    @State private var showDeleteAlert = false
    @State private var showDeletePlaylistConfirm = false
    @State private var showEditSheet = false
    @State private var showAddMusic = false
    @State private var songToAddToPlaylist: DisplayableSong?
    /// Keyboard-navigable selection: ↑/↓ move, ↩ plays — driven by SongListKeyboardNavigator,
    /// works immediately on page switch.
    @State private var selectedSongId: String?
    @State private var keyboardNavToken: UUID?

    var body: some View {
        Group {
            if let vm {
                playlistContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { playlistToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .alert("Remove downloaded playlist?", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { Task { await vm?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
        }
        .deletePlaylistConfirmation(
            playlistName: vm?.name ?? name,
            isPresented: $showDeletePlaylistConfirm,
            hasDownloads: vm?.songs.contains { $0.isDownloaded } ?? false
        ) { purgeDownloads in
            Task { await deletePlaylistMacOS(purgeDownloads: purgeDownloads) }
        }
        .sheet(isPresented: $showEditSheet) {
            PlaylistEditSheet(
                initialName: vm?.name ?? name,
                initialDescription: vm?.playlistDetail?.comment ?? "",
                onSave: { newName, newDesc in
                    Task { await saveEdit(name: newName, description: newDesc) }
                }
            )
        }
        .sheet(isPresented: $showAddMusic) {
            if let vm, let c = container, let serverId = c.serverState.activeServer?.id {
                AddMusicSheet(
                    playlistName: vm.name.isEmpty ? name : vm.name,
                    existingTrackIds: vm.songs.map(\.id)
                ) { added in
                    await AddMusicCommitter.commit(
                        addedSongs: added,
                        playlistId: playlistId,
                        serverId: serverId,
                        existingTrackIds: vm.songs.map(\.id),
                        currentComment: vm.playlistDetail?.comment ?? "",
                        container: c,
                        colorExtractor: colorExtractor
                    )
                    await vm.load()
                }
                .environment(colorExtractor)
                .environment(c.artworkImageCache)
                .environment(\.appContainer, c)
                .frame(minWidth: 480, minHeight: 580)
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let c = container else { return }
            if vm == nil {
                vm = PlaylistDetailViewModel(
                    playlistId: playlistId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    playlistService: c.playlistService,
                    toastService: c.toastService,
                    serverState: c.serverState
                )
            }
            await vm?.load()
        }
    }

    private func playlistContent(_ vm: PlaylistDetailViewModel) -> some View {
        let songs = vm.songs
        let serverId = container?.serverState.activeServer?.id ?? UUID()
        return VStack(spacing: 0) {
            DetailHeroView(
                coverArtId: vm.coverArtId ?? coverArtId,
                title: vm.name.isEmpty ? name : vm.name,
                primaryLine: vm.owner,
                secondaryLine: songs.isEmpty ? nil : String(localized: "\(songs.count) tracks"),
                primaryAction: {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                },
                secondaryAction: {
                    Task {
                        if container?.playerState.isShuffled != true {
                            await container?.playerService.toggleShuffle()
                        }
                        try? await container?.playerService.play(tracks: songs, startIndex: 0)
                    }
                },
                contentTopInset: 26
            )
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                // HStack is required: an overlay lays a bare ViewBuilder's children out like a
                // ZStack, which stacked all four buttons at the same position.
                HStack(spacing: 10) {
                    actionButtons
                }
                .padding(.trailing, 20)
                .padding(.top, 12)
            }

            ScrollViewReader { proxy in
            List(selection: $selectedSongId) {
                if vm.isLoading && songs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if songs.isEmpty, let error = vm.error {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Playlist",
                        subtitle: LocalizedStringKey(error.displayMessage),
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    PlaylistSongRows(
                        songs: songs,
                        serverId: serverId,
                        downloadingIds: vm.downloadingIds,
                        onTap: { index in
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                        },
                        onDownload: (vm.isOffline || vm.isDownloadingPlaylist) ? nil : { songId in
                            Task { await vm.downloadSong(id: songId) }
                        },
                        onRemoveDownload: { songId in
                            Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                        },
                        onRemove: vm.isOffline ? nil : { index in
                            Task { await vm.removeTrack(at: index) }
                        },
                        onReorder: vm.isOffline ? nil : { source, dest in
                            Task { await vm.moveTracks(from: source, to: dest) }
                        },
                        onAddToPlaylist: { song in songToAddToPlaylist = song }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: CassetteMacOSLayout.playerBarReservedHeight / 2)
            }
            .onAppear {
                keyboardNavToken = SongListKeyboardNavigator.shared.activate(
                    songs: { vm.songs },
                    selection: $selectedSongId,
                    scrollTo: { proxy.scrollTo($0) },
                    play: { index in
                        Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                    }
                )
            }
            .onDisappear {
                if let token = keyboardNavToken {
                    SongListKeyboardNavigator.shared.deactivate(token)
                }
            }
            .sheet(item: $songToAddToPlaylist) { song in
                AddToPlaylistSheet(song: song)
            }
            }
        }
        // Full-bleed: the hero extends up under the transparent toolbar, so the page reclaims the
        // strip the floating action buttons (+ / edit / download / delete) used to reserve.
        .ignoresSafeArea(edges: .top)
    }

    private func saveEdit(name newName: String, description: String) async {
        guard let c = container else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDesc = (vm?.playlistDetail?.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty && trimmedName != (vm?.name ?? name) {
            do {
                try await c.playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
                vm?.name = trimmedName
            } catch {
                Logger.playlist.warning("PlaylistDetailMacOS: rename failed: \(error)")
                c.toastService.showError("Failed to rename playlist")
            }
        }

        if trimmedDesc != originalDesc {
            do {
                try await c.playlistService.updateDescription(id: playlistId, description: trimmedDesc)
            } catch {
                Logger.playlist.warning("PlaylistDetailMacOS: description update failed: \(error)")
                c.toastService.showError("Failed to update description")
            }
        }

        await vm?.load()
    }

    private func deletePlaylistMacOS(purgeDownloads: Bool) async {
        guard let c = container else { return }
        do {
            try await c.playlistService.deletePlaylist(id: playlistId, purgeDownloads: purgeDownloads)
            postPlaylistDeleted()
            dismiss()
        } catch {
            Logger.playlist.error("PlaylistDetailMacOS: delete failed: \(error, privacy: .public)")
            c.toastService.showError("Failed to delete playlist")
        }
    }

    @ToolbarContentBuilder
    private var playlistToolbar: some ToolbarContent {
        if showBackButton {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Back")
            }
            .cassetteSharedBackgroundVisibility(.hidden)
        }
    }

    /// Add / edit / download / delete actions, pinned to the hero's top-right corner as an in-page
    /// overlay (the window toolbar placed them over the cover's leading edge).
    @ViewBuilder
    private var actionButtons: some View {
        Button {
            showAddMusic = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .cassetteGlassButton(size: 28)
        }
        .buttonStyle(.borderless)
        .disabled(vm?.isOffline == true || container?.serverState.isOnline != true || vm?.playlistDetail == nil)
        .help("Add Music")

        Button {
            showEditSheet = true
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .cassetteGlassButton(size: 28)
        }
        .buttonStyle(.borderless)
        .disabled(vm?.isOffline == true || container?.serverState.isOnline != true || vm?.playlistDetail == nil)
        .help("Edit Playlist")

        if vm?.isDownloadingPlaylist == true {
            Button {
                Task { await vm?.cancelPlaylistDownload() }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .help("Cancel Download")
        } else if vm?.songs.contains(where: { $0.isDownloaded }) == true {
            // Downloaded → this button manages the LOCAL copy (free space) — distinct from the trash, which
            // deletes the playlist itself. Reuses the existing "Remove downloaded playlist?" confirmation.
            Button {
                showDeleteAlert = true
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .help("Remove Download")
        } else {
            Button {
                Task { await vm?.downloadPlaylist() }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .disabled(vm?.isOffline == true || container?.serverState.isOnline != true)
            .help("Download Playlist")
        }

        Button(role: .destructive) {
            showDeletePlaylistConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .cassetteGlassButton(size: 28)
        }
        .buttonStyle(.borderless)
        .disabled(vm?.isOffline == true)
        .help("Delete Playlist")
    }
}

private struct PlaylistEditSheet: View {
    let initialName: String
    let initialDescription: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editName: String = ""
    @State private var editDescription: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Playlist")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $editName)
                TextField("Description", text: $editDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    onSave(editName, editDescription)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 340)
        .onAppear {
            editName = initialName
            editDescription = initialDescription
        }
    }
}
