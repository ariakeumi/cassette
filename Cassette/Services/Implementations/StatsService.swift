// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Records and manages local playback events (listening history).
///
/// Pure actor — no MainActor, no singleton, no network access.
/// Injected via AppContainer. All persistence uses a private ModelContext;
/// PlaybackEvent PersistentModel instances never leave this actor.
actor StatsService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    func recordPlayback(_ event: PlaybackEventDTO, trigger: String = "") async {
        let context = ModelContext(modelContainer)
        let model = PlaybackEvent(
            trackId: event.trackId,
            trackTitle: event.trackTitle,
            albumId: event.albumId,
            albumTitle: event.albumTitle,
            artistId: event.artistId,
            artistName: event.artistName,
            genre: event.genre,
            timestamp: event.timestamp,
            durationListened: event.durationListened,
            trackDuration: event.trackDuration,
            wasCompleted: event.wasCompleted,
            serverId: event.serverId
        )
        context.insert(model)
        do {
            try context.save()
            let artistIdForLog = event.artistId ?? "nil"
            let durationForLog = String(format: "%.1f", event.durationListened)
            Logger.stats.debug(
                "[INSERT] trigger=\(trigger, privacy: .public) trackId=\(event.trackId, privacy: .public) artistId=\(artistIdForLog, privacy: .public) durationListened=\(durationForLog, privacy: .public)s startedAt=\(event.timestamp, privacy: .public) completed=\(event.wasCompleted, privacy: .public) serverId=\(event.serverId, privacy: .public)"
            )
        } catch {
            Logger.stats.error("Failed to save playback event: \(error, privacy: .public)")
        }
    }

    func eventCount(forServer serverId: String) async -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Most recent playback events (≥30s listens, as recorded), newest first.
    /// Returns Sendable DTOs — PlaybackEvent instances never leave this actor.
    func recentEvents(limit: Int, serverId: String) async -> [PlaybackEventDTO] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let events = (try? context.fetch(descriptor)) ?? []
        return events.map { event in
            PlaybackEventDTO(
                trackId: event.trackId,
                trackTitle: event.trackTitle,
                albumId: event.albumId,
                albumTitle: event.albumTitle,
                artistId: event.artistId,
                artistName: event.artistName,
                genre: event.genre,
                timestamp: event.timestamp,
                durationListened: event.durationListened,
                trackDuration: event.trackDuration,
                wasCompleted: event.wasCompleted,
                serverId: event.serverId
            )
        }
    }

    func deleteAllEvents(forServer serverId: String) async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        do {
            let events = try context.fetch(descriptor)
            guard !events.isEmpty else { return }
            for event in events {
                context.delete(event)
            }
            try context.save()
            Logger.stats.info("Deleted \(events.count) event(s) for serverId=\(serverId, privacy: .public)")
        } catch {
            Logger.stats.error("Failed to delete events for serverId=\(serverId, privacy: .public): \(error, privacy: .public)")
        }
    }
}
