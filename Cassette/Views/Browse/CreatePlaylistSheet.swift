// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var viewModel: CreatePlaylistViewModel?
    @State private var selectedGradient: PlaylistGradientShape?
    /// Whether the PHOTO is the chosen cover. Separate from "a photo is picked" (pendingImage) so a picked
    /// photo's preview survives switching to another cover and back.
    @State private var photoIsCover = false
    @FocusState private var nameFieldFocused: Bool

    var onCreated: ((PlaylistWithSongs) -> Void)? = nil


    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel?.isCreating == true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let vm = viewModel, let c = container else { return }
                        Task {
                            if let created = await vm.create() {
                                await applyCover(playlistId: created.id, container: c)
                                onCreated?(created)
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel?.isCreating == true {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!(viewModel?.canCreate ?? false))
                }
            }
        }
        .tint(Color.cassetteAccent)
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = CreatePlaylistViewModel(
                    playlistService: c.playlistService,
                    toastService: c.toastService
                )
            }
            nameFieldFocused = true
        }
    }

    @ViewBuilder
    private func content(_ vm: CreatePlaylistViewModel) -> some View {
        ScrollView {
            VStack(spacing: CassetteSpacing.xl) {
                coverCarousel(vm)
                    .padding(.top, CassetteSpacing.s)

                VStack(spacing: CassetteSpacing.s) {
                    // Editorial centered title + discreet description, no field chrome, no separators (AM style).
                    TextField("Playlist Title", text: Bindable(vm).name)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .padding(.vertical, CassetteSpacing.s)

                    TextField("Description", text: Bindable(vm).description, axis: .vertical)
                        .multilineTextAlignment(.center)
                        .lineLimit(1...4)
                }
                .padding(.horizontal, CassetteSpacing.l)
            }
            .padding(.top, CassetteSpacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var hasPhoto: Bool {
        return false
    }

    private var showsPhotoOption: Bool {
        return false
    }

    private var photoPreviewImage: PlatformImage? {
        return nil
    }


    /// Create-flow cover carousel (Apple-Music direction). The gradient previews show the neutral base color
    /// (an empty playlist has no first track to derive from yet — that derivation is the edit flow's job);
    /// forms differ by geometry. The live title renders into the gradient cards.
    private func coverCarousel(_ vm: CreatePlaylistViewModel) -> some View {
        PlaylistCoverCarousel(
            title: vm.name,
            selectedGradient: selectedGradient,
            isPhotoSelected: photoIsCover,
            photoPreview: photoPreviewImage,
            showsPhotoOption: showsPhotoOption,
            leadingLabel: "None",
            onSelectLeading: {
                selectedGradient = nil
                photoIsCover = false        // keep pendingImage so the photo card preview survives
            },
            onSelectPhoto: {
                // Swipe settled on the photo card → focus the photo as cover, NO modal.
                selectedGradient = nil
                photoIsCover = true
            },
            onRequestPhotoPicker: {
                selectedGradient = nil
                photoIsCover = true
            },
            onSelectGradient: { shape in
                selectedGradient = shape
                photoIsCover = false        // keep pendingImage so the photo card preview survives
            }
        )
    }

    /// Applies the chosen cover after the playlist is created: render+cache+upload via PlaylistCoverManager,
    /// and persist a gradient choice client-side.
    private func applyCover(playlistId: String, container c: AppContainer) async {
        let manager = PlaylistCoverManager(
            serverState: c.serverState,
            serverService: c.serverService,
            downloadService: c.downloadService,
            artworkImageCache: c.artworkImageCache
        )
        if let shape = selectedGradient {
            // Empty playlist at creation → neutral base color now; first-track derivation is Phase 2b.
            let spec = PlaylistGradientSpec.neutral(shape: shape)
            await manager.applyGradientCover(spec, playlistId: playlistId)
            if let serverId = c.serverState.activeServer?.id {
                PlaylistCoverStore(modelContainer: c.modelContainer)
                    .save(spec, playlistId: playlistId, serverId: serverId, isUserPicked: true)
            }
            return
        }
    }
}
