// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

struct RootViewMacOS: View {
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
    // Local mutable copy for native sidebar drag-to-reorder; synced from @Query on count changes.
    @State private var localPinnedItems: [PinnedItem] = []
    @State private var selection: SidebarDestination? = .section(.home)
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isShowingFullPlayer = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var navigationPath = NavigationPath()
    // 侧边栏固定播放列表的重命名
    @State private var showRenameAlert = false
    @State private var renameTarget: PinnedItem?
    @State private var renameText: String = ""

    /// Pinned items of type playlist, in sidebar (sortOrder) order — targets for the Cmd+1…9 shortcuts.
    private var pinnedPlaylistItems: [PinnedItem] {
        pinnedItems.filter { $0.itemType == PinnedItemType.playlist.rawValue }
    }

    /// Cmd+1…9 jump to the nth pinned playlist (sidebar Pinned order). Hidden buttons register
    /// the shortcuts while staying invisible.
    @ViewBuilder
    private var pinnedPlaylistShortcuts: some View {
        ForEach(Array(pinnedPlaylistItems.prefix(9).enumerated()), id: \.element.id) { pair in
            // ⌘N 实际路由在 KeyboardInterceptor（搜索框聚焦时 hidden-button 快捷键会被吞），
            // 这里保留 Button 仅用于注册与菜单/无障碍语义。
            Button {
                searchQuery = ""
                selection = .pinned(pair.element.id)
            } label: {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private static let digitKeyEquivs: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    private var splitContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 120)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.6), location: 0.5),
                    .init(color: Color(nsColor: .windowBackgroundColor), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            BottomPlayerBar(onArtworkTap: { withAnimation { isShowingFullPlayer = true } })
                .frame(maxWidth: 600)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .searchable(text: $searchQuery, placement: .sidebar)
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) {
            // Return commits the search — release the field so bare ↑/↓/↩ reach the
            // result list (SongListKeyboardNavigator) instead of typing in the NSTextView.
            isSearchFocused = false
        }
    }

    var body: some View {
        rootStack
            .frame(minWidth: 1100, minHeight: 500)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .onChange(of: selection) { _, _ in
                if isShowingFullPlayer { withAnimation { isShowingFullPlayer = false } }
            }
            .alert("重命名播放列表", isPresented: $showRenameAlert) {
                TextField("新名称", text: $renameText)
                Button("确定") { commitRename() }
                Button("取消", role: .cancel) { showRenameAlert = false }
            } message: {
                Text("输入新的播放列表名称")
            }
            .modifier(RootPlaybackWiring(
                isShowingFullPlayer: $isShowingFullPlayer,
                isSearchFocused: $isSearchFocused
            ))
            .modifier(RootNavigationWiring(
                selection: $selection,
                isShowingFullPlayer: $isShowingFullPlayer,
                navigationPath: $navigationPath,
                searchQuery: $searchQuery
            ))
    }

    @ViewBuilder
    private var rootStack: some View {
        ZStack {
            MainWindowConfigurator(isFullPlayerVisible: isShowingFullPlayer)
                .frame(width: 0, height: 0)

            splitContent

            pinnedPlaylistShortcuts

            if isShowingFullPlayer {
                FullPlayerExpandedView(isPresented: $isShowingFullPlayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1)
                    .toolbar(.hidden, for: .windowToolbar)
            }
        }
    }

    // MARK: - Playback

    private func handleTogglePlayPause() async {
        guard let container else { return }
        if container.playerState.playbackState == .playing {
            await container.playerService.pause()
        } else {
            await container.playerService.resume()
        }
    }

    private func commitRename() {
        guard let item = renameTarget,
              let playlistService = container?.playlistService else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        Task {
            do {
                try await playlistService.renamePlaylist(id: item.itemId, newName: newName)
                container?.pinService.renamePinnedItem(
                    itemType: .playlist, itemId: item.itemId, newName: newName
                )
            } catch {
                Logger.playlist.error("Rename pinned playlist failed: \(error, privacy: .public)")
            }
        }
    }

    /// Volume stepping for the ⌘↑ / ⌘↓ shortcuts. Mute-aware: PlayerService reads the live engine
    /// volume, so stepping up from muted starts at 0.1 rather than overshooting the pre-mute level.
    private func adjustVolume(by delta: Float) {
        guard let container else { return }
        Task { await container.playerService.adjustVolume(by: delta) }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
                sidebarRow(.home)
            }

            Section("Library") {
                sidebarRow(.songs)
                sidebarRow(.albums)
                sidebarRow(.artists)
                sidebarRow(.playlists)
                sidebarRow(.favorites)
            }

            if !localPinnedItems.isEmpty {
                Section("Pinned") {
                    ForEach(localPinnedItems) { item in
                        pinnedRow(item)
                            .tag(SidebarDestination.pinned(item.id))
                    }
                    .onMove { source, destination in
                        // Native List reorder; persist through PinService (writes sortOrder + saves)
                        // so pinned order has a single source of truth.
                        localPinnedItems.move(fromOffsets: source, toOffset: destination)
                        container?.pinService.reorder(items: localPinnedItems)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            userFooter
        }
        .onAppear { localPinnedItems = pinnedItems }
        .onChange(of: pinnedItems.count) { _, _ in localPinnedItems = pinnedItems }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.displayLabel, systemImage: section.systemImage)
            .tag(SidebarDestination.section(section))
    }

    @ViewBuilder
    private func pinnedRow(_ item: PinnedItem) -> some View {
        // 播放列表固定项：不显示任何图标，仅文字；专辑固定项仍显示封面缩略图
        Label {
            Text(item.displayName)
        } icon: {
            if item.itemType != PinnedItemType.playlist.rawValue {
                if let coverArtId = item.coverArtId {
                    CoverArtView(
                        id: coverArtId,
                        size: 22,
                        cornerRadius: 3,
                        placeholderSystemImage: "square.stack"
                    )
                    .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "square.stack")
                }
            }
        }
        .contextMenu {
            Button {
                selection = .pinned(item.id)
            } label: {
                Label("Open", systemImage: "arrow.up.right")
            }

            Divider()

            Button(role: .destructive) {
                if let type = PinnedItemType(rawValue: item.itemType) {
                    container?.pinService.unpin(itemType: type, itemId: item.itemId)
                }
            } label: {
                Label("取消固定", systemImage: "pin.slash")
            }

            if item.itemType == PinnedItemType.playlist.rawValue {
                Button("重命名") {
                    renameTarget = item
                    renameText = item.displayName
                    showRenameAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private var userFooter: some View {
        if let server = container?.serverState.activeServer {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.displayName)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(server.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !searchQuery.isEmpty {
                    SearchView(searchQuery: $searchQuery, path: $navigationPath)
                } else {
                    detailView(for: selection ?? .section(.home))
                }
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .album(let album):
                    AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                case .artist(let artist):
                    ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                case .playlist(let playlist):
                    PlaylistDetailMacOS(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArt)
                case .downloadedAlbum(let display):
                    AlbumDetailMacOS(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId)
                case .albumById(let id, let name, _, let coverArtId):
                    AlbumDetailMacOS(albumId: id, albumName: name, coverArtId: coverArtId)
                case .playlistById(let id, let name, let coverArtId):
                    PlaylistDetailMacOS(playlistId: id, name: name, coverArtId: coverArtId)
                case .offlineAlbum(let album):
                    AlbumDetailMacOS(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
                case .offlineArtist(let artist):
                    OfflineArtistAlbumsView(artist: artist)
                case .artistById(let id, let name, let coverArtId):
                    ArtistDetailMacOS(artistId: id, artistName: name, coverArtId: coverArtId)
                case .artistBestOf(let id, let name, let coverArtId):
                    ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func detailView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .section(let section):
            sectionView(for: section)
        case .pinned(let id):
            pinnedDetail(for: id)
                .id(id)
        }
    }

    @ViewBuilder
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .home:      HomeView()
        case .albums:    AlbumsListView()
        case .artists:   ArtistsListMacOS()
        case .songs:     SongsListView()
        case .playlists: PlaylistListView()
        case .favorites: FavoritesView()
        }
    }

    @ViewBuilder
    private func pinnedDetail(for id: String) -> some View {
        if let item = pinnedItems.first(where: { $0.id == id }) {
            switch PinnedItemType(rawValue: item.itemType) {
            case .album:
                AlbumDetailMacOS(
                    albumId: item.itemId,
                    albumName: item.displayName,
                    coverArtId: item.coverArtId,
                    showBackButton: false
                )
            case .playlist:
                PlaylistDetailMacOS(
                    playlistId: item.itemId,
                    name: item.displayName,
                    coverArtId: item.coverArtId,
                    showBackButton: false
                )
            case .none:
                ContentUnavailableView("Unknown item type", systemImage: "questionmark")
            }
        } else {
            ContentUnavailableView("Item not found", systemImage: "pin.slash")
        }
    }
}

/// Playback-related notification wiring (transport, volume, player surfaces), extracted from
/// `body` so the type checker doesn't face one giant modifier chain.
private struct RootPlaybackWiring: ViewModifier {
    @Environment(\.appContainer) private var container
    @Binding var isShowingFullPlayer: Bool
    var isSearchFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .cassetteTogglePlayPause)) { _ in
                Task { await togglePlayPause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteSkipNext)) { _ in
                Task { try? await container?.playerService.skipToNext() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteSkipPrevious)) { _ in
                Task { try? await container?.playerService.skipToPrevious() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleShuffle)) { _ in
                Task { await container?.playerService.toggleShuffle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleRepeat)) { _ in
                Task {
                    guard let container else { return }
                    await container.playerService.setRepeatMode(container.playerState.repeatMode.next)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteVolumeUp)) { _ in
                adjustVolume(by: 0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteVolumeDown)) { _ in
                adjustVolume(by: -0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteOpenFullPlayer)) { _ in
                withAnimation { isShowingFullPlayer = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteOpenFullPlayerLyrics)) { _ in
                withAnimation { isShowingFullPlayer = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleLyrics)) { _ in
                if isShowingFullPlayer {
                    if UserDefaults.standard.bool(forKey: "cassette.fullPlayerLastPanel") {
                        // Lyrics already showing — ⌘L closes the player.
                        withAnimation { isShowingFullPlayer = false }
                    } else {
                        // On the queue panel — ⌘L switches to lyrics.
                        NotificationCenter.default.post(name: .cassetteOpenFullPlayerLyrics, object: nil)
                    }
                } else {
                    // Mirror BottomPlayerBar's lyrics button: remember lyrics panel, then open.
                    UserDefaults.standard.set(true, forKey: "cassette.fullPlayerLastPanel")
                    NotificationCenter.default.post(name: .cassetteOpenFullPlayerLyrics, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteFocusSearch)) { _ in
                isSearchFocused.wrappedValue = true
            }
    }

    private func togglePlayPause() async {
        guard let container else { return }
        if container.playerState.playbackState == .playing {
            await container.playerService.pause()
        } else {
            await container.playerService.resume()
        }
    }

    /// Mute-aware volume stepping: PlayerService reads the live engine volume, so stepping up
    /// from muted starts at the stepped value rather than overshooting the pre-mute level.
    private func adjustVolume(by delta: Float) {
        guard let container else { return }
        Task { await container.playerService.adjustVolume(by: delta) }
    }
}

/// Navigation notification wiring (sidebar section selection + global navigate-to destinations).
private struct RootNavigationWiring: ViewModifier {
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
    @Binding var selection: SidebarDestination?
    @Binding var isShowingFullPlayer: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var searchQuery: String

    private var pinnedPlaylistItems: [PinnedItem] {
        pinnedItems.filter { $0.itemType == PinnedItemType.playlist.rawValue }
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .cassetteSelectHome)) { _ in
                withAnimation { isShowingFullPlayer = false }
                searchQuery = "" // 退出搜索态，让目标页面可见
                if !navigationPath.isEmpty { navigationPath = NavigationPath() } // 弹回主页根视图
                selection = .section(.home)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteSelectSongs)) { _ in
                searchQuery = "" // 退出搜索态，让目标页面可见
                selection = .section(.songs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteSelectAlbums)) { _ in
                searchQuery = "" // 同上
                selection = .section(.albums)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteOpenPinnedPlaylist)) { note in
                guard let index = note.userInfo?["index"] as? Int else { return }
                guard pinnedItems.indices.contains(index),
                      pinnedItems[index].itemType == PinnedItemType.playlist.rawValue else { return }
                let item = pinnedItems[index]
                searchQuery = ""
                isShowingFullPlayer = false
                selection = .pinned(item.id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToAlbum)) { note in
                guard let id   = note.userInfo?["albumId"]   as? String,
                      let name = note.userInfo?["albumName"]  as? String else { return }
                let coverArtId = note.userInfo?["coverArtId"] as? String
                withAnimation { isShowingFullPlayer = false }
                searchQuery = ""
                selection = .section(.home)
                navigationPath.append(HomeDestination.albumById(id: id, name: name, subtitle: "", coverArtId: coverArtId))
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToArtist)) { note in
                guard let id   = note.userInfo?["artistId"]   as? String,
                      let name = note.userInfo?["artistName"]  as? String else { return }
                let coverArtId = note.userInfo?["coverArtId"] as? String
                withAnimation { isShowingFullPlayer = false }
                searchQuery = ""
                selection = .section(.home)
                navigationPath.append(HomeDestination.artistById(id: id, name: name, coverArtId: coverArtId))
            }
            .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToPlaylist)) { note in
                guard let id   = note.userInfo?["playlistId"] as? String,
                      let name = note.userInfo?["name"]       as? String else { return }
                let coverArtId = note.userInfo?["coverArtId"] as? String
                withAnimation { isShowingFullPlayer = false }
                searchQuery = ""
                selection = .section(.home)
                navigationPath.append(HomeDestination.playlistById(id: id, name: name, coverArtId: coverArtId))
            }
    }
}

// MARK: - Window configurator

private struct MainWindowConfigurator: NSViewRepresentable {
    let isFullPlayerVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setFrameAutosaveName("CassetteMainWindow")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            // titlebarAppearsTransparent must be true unconditionally: on macOS 26 (Liquid Glass)
            // the titlebar material bleeds a frosted-glass overlay into scrolled content when
            // this is false, and no SwiftUI modifier can suppress it. The full-player overlay
            // sets it to true anyway, so keeping it true at all times is consistent.
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = isFullPlayerVisible
        }
    }
}

