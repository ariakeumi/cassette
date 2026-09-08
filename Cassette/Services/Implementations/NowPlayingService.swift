// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import MediaPlayer
import OSLog

/// Manages MPNowPlayingInfoCenter + MPRemoteCommandCenter.
/// Active from v1 (lockscreen, Control Center, AirPods, Apple Watch).
/// Architected as the direct extension point for CarPlay (v1.2) — no refactor needed.
actor NowPlayingService: NowPlayingServiceProtocol {
    private let playerService: any PlayerServiceProtocol
    private let artworkLoader = ArtworkLoader()
    private let artworkImageCache: ArtworkImageCache
    private var commandsRegistered = false
    private var currentSong: NowPlayingSnapshot?
    /// Wired after init — FavoritesService is built later in AppContainer, same as the
    /// PlayerService→NowPlayingService link.
    private var favoritesService: (any FavoritesServiceProtocol)?

    init(playerService: any PlayerServiceProtocol, artworkImageCache: ArtworkImageCache) {
        self.playerService = playerService
        self.artworkImageCache = artworkImageCache
    }

    func setFavoritesService(_ service: any FavoritesServiceProtocol) {
        favoritesService = service
    }

    // MARK: - Lifecycle

    func start() async {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let playerService = playerService

        // Register every command handler SYNCHRONOUSLY, on the MAIN THREAD, in ONE atomic block — before any
        // actor suspension and before the first now-playing info is set. MPRemoteCommandCenter is a main-thread
        // API: registering it from the NowPlayingService actor (off-main) races the system's single
        // setSupportedCommands snapshot — capturing only {Play, Pause} and never re-snapshotting, so Next /
        // Previous / scrubber showed greyed out (partial/random by run = the registration-vs-snapshot race).
        // One main-thread block guarantees the supported set is COMPLETE at that snapshot. addTarget is what
        // makes a command "supported"; isEnabled (in updateRemoteCommandsAvailability) only greys/ungreys it.
        await MainActor.run {
            let center = MPRemoteCommandCenter.shared()

            center.playCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.resume()
                }
                return .success
            }

            center.pauseCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.pause()
                }
                return .success
            }

            center.togglePlayPauseCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    await playerService.togglePlayPause()
                }
                return .success
            }

            center.nextTrackCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    do {
                        try await playerService.skipToNext()
                    } catch {
                        Logger.nowPlaying.error("[PLAYBACK] skipToNext failed: \(error, privacy: .public)")
                    }
                }
                return .success
            }

            center.previousTrackCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    do {
                        try await playerService.skipToPrevious()
                    } catch {
                        Logger.nowPlaying.error("[PLAYBACK] skipToPrevious failed: \(error, privacy: .public)")
                    }
                }
                return .success
            }

            // macOS Control Center may route the previous-track gesture through skipBackwardCommand
            // instead of previousTrackCommand. Register both so the gesture works on either path.
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 0)]
            center.skipBackwardCommand.addTarget { [playerService] _ in
                Task.detached(priority: .userInitiated) {
                    try? await playerService.skipToPrevious()
                }
                return .success
            }

            // Favourite the playing track from a remote surface. Registered here with the rest so it
            // is inside the system's single supported-commands snapshot (see the note above).
            //
            // NOTE ON WHERE THIS SHOWS UP: the system Now Playing UI — Control Center — has no slot
            // for a like button and will not render one, whatever we register. This command reaches
            // the surfaces that DO have one: CarPlay's Now Playing
            // and the Apple Watch remote. Registering it costs nothing and is what CarPlay will read
            // when that scene lands.
            center.likeCommand.localizedTitle = String(localized: "Add to Favorites")
            center.likeCommand.addTarget { [weak self] _ in
                Task { await self?.toggleFavoriteForCurrentTrack() }
                return .success
            }

            center.changePlaybackPositionCommand.addTarget { [playerService] event in
                guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                let position = seekEvent.positionTime
                Task.detached(priority: .userInitiated) {
                    await playerService.seek(to: position)
                }
                return .success
            }
        }
    }

    func stop() async {
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        postDiscordRPC(.stopped)
    }

    // MARK: - Update

    func update(with snapshot: NowPlayingSnapshot) async {
        updateRemoteCommandsAvailability()

        if snapshot.artworkURL == nil {
            // Position-only update (pause/resume/seek): merge into the existing dict so
            // artwork already loaded for the current track is preserved.
            await MainActor.run {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyTitle] = snapshot.title
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
                info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
                info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.playbackRate
                info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
                if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
            }
            if snapshot.playbackRate == 0 {
                postDiscordRPC(.stopped)
            } else if let song = currentSong {
                postDiscordRPC(.nowPlaying(.init(
                    title: song.title,
                    artist: song.artist ?? "",
                    album: song.album ?? "",
                    duration: song.duration,
                    startedAt: Date().timeIntervalSince1970
                )))
            }
            return
        }

        // New track: build from scratch so stale artwork from the previous track is cleared
        // before the new one loads. Text metadata is committed first so the lockscreen
        // doesn't flash empty while the artwork fetch is in progress.
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
        currentSong = snapshot
        await refreshLikeCommandState()
        let baseInfo = info
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo
            MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
        }
        postDiscordRPC(.nowPlaying(.init(
            title: snapshot.title,
            artist: snapshot.artist ?? "",
            album: snapshot.album ?? "",
            duration: snapshot.duration,
            startedAt: Date().timeIntervalSince1970
        )))

        // Fast path: image already in ArtworkImageCache (pre-loaded when the card was visible).
        if let coverArtId = snapshot.coverArtId,
           let cachedImage = await artworkImageCache.cached(for: coverArtId, tier: .hero) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
            }
            return
        }

        // Slow path: fetch from URL and populate both caches.
        if let artworkURL = snapshot.artworkURL,
           let artwork = await artworkLoader.artwork(for: artworkURL, headers: snapshot.artworkHeaders) {
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
            }
        }
    }

    // MARK: - Periodic position push

    func pushPosition(elapsed: TimeInterval, rate: Float, duration: TimeInterval) async {
        guard elapsed >= 0, duration > 0, elapsed <= duration else { return }
        await MainActor.run {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
            info[MPMediaItemPropertyPlaybackDuration] = duration
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    // MARK: - Favourite

    /// Stars or unstars whatever is playing, driven from a remote surface (CarPlay, Watch).
    private func toggleFavoriteForCurrentTrack() async {
        guard let favoritesService, let songId = currentSong?.songId else { return }
        let wasFavorite = await MainActor.run { favoritesService.isFavorite(itemType: .song, itemId: songId) }
        do {
            if wasFavorite {
                try await favoritesService.unstar(itemType: .song, itemId: songId)
            } else {
                try await favoritesService.star(itemType: .song, itemId: songId)
            }
            await refreshLikeCommandState()
            Logger.nowPlaying.info("[REMOTE] \(wasFavorite ? "unstarred" : "starred", privacy: .public) '\(songId, privacy: .public)' from a remote surface")
        } catch {
            Logger.nowPlaying.warning("[REMOTE] favourite toggle failed for '\(songId, privacy: .public)': \(error, privacy: .public)")
        }
    }

    /// Mirrors the stored favourite state onto the command, so a remote surface that draws the
    /// button filled/unfilled draws it right.
    private func refreshLikeCommandState() async {
        let songId = currentSong?.songId
        let isFavorite: Bool
        if let songId, let favoritesService {
            isFavorite = await MainActor.run { favoritesService.isFavorite(itemType: .song, itemId: songId) }
        } else {
            isFavorite = false
        }
        await MainActor.run {
            let command = MPRemoteCommandCenter.shared().likeCommand
            command.isEnabled = songId != nil
            command.isActive = isFavorite
        }
    }

    // MARK: - Remote command availability

    private func updateRemoteCommandsAvailability() {
        let center = MPRemoteCommandCenter.shared()
        // play/pause/togglePlayPause remain always-on.
        Logger.nowPlaying.debug("[REMOTE] updateRemoteCommandsAvailability — nextEnabled=true")
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled BEFORE=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled BEFORE=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        appendToDebugLog("[RCC] updateRemoteCommandsAvailability called")
        appendToDebugLog("[RCC] nextTrack BEFORE=\(center.nextTrackCommand.isEnabled)")
        appendToDebugLog("[RCC] previousTrack BEFORE=\(center.previousTrackCommand.isEnabled)")
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled AFTER=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled AFTER=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        appendToDebugLog("[RCC] nextTrack AFTER=\(center.nextTrackCommand.isEnabled)")
        appendToDebugLog("[RCC] previousTrack AFTER=\(center.previousTrackCommand.isEnabled)")
    }

    // MARK: - Discord RPC

    private nonisolated func postDiscordRPC(_ event: DiscordRPCEvent) {
        let port = 47832
        let urlString: String
        var body: Data?

        switch event {
        case .nowPlaying(let info):
            urlString = "http://localhost:\(port)/now-playing"
            body = try? JSONEncoder().encode(info)
        case .stopped:
            urlString = "http://localhost:\(port)/playback-stopped"
        }

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func appendToDebugLog(_ message: String) {
        // Forward to the off-actor, opt-in, size-capped logger — no synchronous disk I/O on the playback
        // actor or the track-change path (audit finding L4). Disabled by default; see RemoteCommandDebugLog.
        RemoteCommandDebugLog.log(message)
    }
}

/// Opt-in, size-capped, off-actor file logger for the MPRemoteCommandCenter skip/previous diagnostic.
///
/// This is the active diagnostic for the remote-command (next/previous) bug, so the capability is kept —
/// but made safe. It is OFF by default and enabled at runtime via the UserDefaults flag `debug.rccFileLog`
/// (so it can be turned on for a release build on a real device, unlike a `#if DEBUG` gate). When enabled it
/// appends on a background serial queue — never blocking the playback actor — and rotates the file at a size
/// cap so `cassette_debug.log` can never grow unbounded.
private enum RemoteCommandDebugLog {
    /// Runtime toggle, default OFF. Set this UserDefaults bool to true to capture the log while diagnosing.
    nonisolated static let enabledKey = "debug.rccFileLog"
    /// Rotate when the active log reaches this size; total on disk is bounded to ~2x this (.log + .log.1).
    private nonisolated static let maxBytes = 256 * 1024
    private nonisolated static let queue = DispatchQueue(label: "fr.mathieu-dubart.cassette.rcc-debug-log", qos: .utility)

    nonisolated static func log(_ message: String) {
    }
}

private nonisolated enum DiscordRPCEvent {
    case nowPlaying(DiscordNowPlayingInfo)
    case stopped
}

private nonisolated struct DiscordNowPlayingInfo: Encodable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let startedAt: Double
}
