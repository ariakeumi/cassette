// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import OSLog
import Foundation

@main
struct CassetteApp: App {
    @State private var container: AppContainer?
    @Environment(\.scenePhase) private var scenePhase

    // Statics for BGTask handler access — set once after AppContainer init.
    // nonisolated(unsafe) is intentional: the BGTask closure runs off-actor;
    // these are written once on MainActor and read in a non-isolated context.

    init() {
        // TEMP-DIAG 诊断1：确认测试进程身份
        Logger(subsystem: "app.cassette", category: "Diag").notice("DIAG process pid=\(ProcessInfo.processInfo.processIdentifier) bundlePath=\(Bundle.main.bundlePath, privacy: .public)")
        // Restore the user's global Play/Pause hotkey (system-wide, registered via Carbon).
        GlobalHotkeyManager.shared.apply(GlobalPlayPauseHotkey.load())
        // Space = Play/Pause anywhere in the app (text fields and the hotkey recorder pass through).
        KeyboardInterceptor.install()
    }


    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        // .toastOverlay() must be the INNERMOST modifier: a toast pill now renders a
                        // CoverArtView, which reads @Environment(ArtworkImageCache.self) / appContainer.
                        // An overlay's content only inherits environments applied AFTER the overlay
                        // modifier (envs applied to the primary content below it do NOT reach the
                        // overlay's own view). So the env injections must sit below .toastOverlay().
                        .toastOverlay()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                        .environment(container.toastService)
                } else {
                    ProgressView()
                }
            }
            .tint(CassetteColors.accent)
            .onAppear {
                NSApplication.shared.windows
                    .first { $0.title == "Mini Player" }?
                    .close()
            }
            .task {
                guard container == nil else { return }
                Logger.boot.notice("🟡 AppContainer init start")
                guard let newContainer = try? AppContainer() else { return }
                Logger.boot.notice("🟡 setup() start")
                await newContainer.setup()
                // Start reachability before the UI is interactive so serverState.isOnline
                // is corrected from its optimistic default before any view loads data.
                newContainer.networkMonitor.start(serverState: newContainer.serverState)
                Logger.boot.notice("🟡 setup() done — nowPlayingService.start()")
                await newContainer.nowPlayingService.start()
                AppContainer.invalidateCoverArtCacheIfNeeded(artworkCache: newContainer.artworkImageCache)
                AppContainer.sweepLegacyCoverArtFiles()
                Task { await AppContainer.migrateAudioExtensionsIfNeeded(modelContainer: newContainer.modelContainer, audioStreamCache: newContainer.audioStreamCache) }
                Task { await AppContainer.migrateM4AFaststartIfNeeded(modelContainer: newContainer.modelContainer) }
                Logger.boot.notice("🟡 container = newContainer (views will render)")
                container = newContainer
                Logger.boot.notice("🟡 loadPersistedState() start")
                // loadPersistedState must complete before restoreSession so the active
                // server is known when prepareCurrentTrackForRestoration resolves the URL.
                await newContainer.serverService.loadPersistedState()
                Logger.boot.notice("🟡 loadPersistedState() done — activeServer = \(String(describing: newContainer.serverState.activeServer?.baseURL), privacy: .public)")
                await newContainer.playerService.restoreSession()
                Task { await runCoverArtGarbageCollection(container: newContainer) }
                Task { await newContainer.widgetSyncService.fullSync() }
            }
            .task(id: container?.serverState.isOnline) {
                guard let c = container, c.serverState.isOnline else { return }
                await c.playerService.handleNetworkRestored()
                await c.listenBrainzService.flushOfflineQueue()
            }
            .frame(minHeight: 580)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                guard let c = container else { return }
                // Stop AVAudioEngine synchronously — prevents HALC frame accumulation during teardown.
                c.playerService.stopAudioEngineSync()
                // Fire-and-forget the async stops. The old code blocked the main thread on a
                // semaphore waiting for this Task — but the Task inherits MainActor and stop()
                // ends on MainActor.run, so the blocked main thread deadlocked it and every quit
                // burned the full 1.5s timeout. The sync engine stop above covers what matters.
                Task { [c] in
                    await c.playerService.stop()
                    await c.nowPlayingService.stop()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, let c = container else { return }
            Task {
                let snapshot = SessionPayload(
                    currentIndex: c.playerState.currentIndex,
                    currentPosition: c.playerState.position,
                    queue: c.playerState.queue,
                    currentTrack: c.playerState.currentTrack,
                    repeatMode: c.playerState.repeatMode,
                    isShuffled: c.playerState.isShuffled,
                    originalQueue: await c.playerService.originalQueueForSession()
                )
                await c.sessionService.save(playerState: snapshot)
            }
            Logger.session.info("App backgrounded — session flushed")
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands {
            CassetteCommands()
        }

        CassetteSettingsScene(container: container)

        Window("Mini Player", id: "mini-player") {
            Group {
                if let container {
                    MiniPlayerWindowView()
                        .environment(\.appContainer, container)
                        .environment(container.dominantColorExtractor)
                        .environment(container.artworkImageCache)
                        .modelContainer(container.modelContainer)
                } else {
                    MiniPlayerWindowView()
                }
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 136)
        .defaultPosition(.topTrailing)
        .restorationBehavior(.disabled)
    }

    // MARK: - Cover art garbage collection

    @MainActor
    private func runCoverArtGarbageCollection(container: AppContainer) async {
        let context = container.modelContainer.mainContext
        var referencedIds: Set<String> = []

        let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
        for album in albums {
            if let id = album.coverArtId { referencedIds.insert(id) }
        }

        let tracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        for track in tracks {
            if let id = track.coverArtId { referencedIds.insert(id) }
        }

        let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
        for playlist in playlists {
            if let id = playlist.coverArtId { referencedIds.insert(id) }
        }

        let pinned = (try? context.fetch(FetchDescriptor<PinnedItem>())) ?? []
        for item in pinned {
            if let id = item.coverArtId { referencedIds.insert(id) }
        }

        await container.downloadService.garbageCollectOrphanedCovers(referencedIds: referencedIds)
    }
}

