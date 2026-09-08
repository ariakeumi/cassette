// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

actor ListenBrainzRecommendationProvider: RecommendationProvider {
    private let client: ListenBrainzClient
    private let libraryService: any LibraryServiceProtocol

    init(
        client: ListenBrainzClient,
        libraryService: any LibraryServiceProtocol
    ) {
        self.client = client
        self.libraryService = libraryService
    }

    // MARK: - RecommendationProvider

    func similarArtists(toArtistID artistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
        // Resolve Subsonic artist ID → MBID via getArtistInfo2
        let mbid: String
        do {
            guard let resolved = try await libraryService.getArtistMBID(forArtistID: artistID) else {
                Logger.listenBrainz.debug("similarArtists: no MBID for artistID=\(artistID, privacy: .public)")
                return []
            }
            mbid = resolved
        } catch {
            Logger.listenBrainz.warning("similarArtists: MBID lookup failed for artistID=\(artistID, privacy: .public)")
            return []
        }

        // Fetch from LB (up to 18, pre-sorted by score desc)
        let dtos: [LBSimilarArtistDTO]
        do {
            dtos = try await client.similarArtists(mbid: mbid)
        } catch {
            Logger.listenBrainz.warning("similarArtists: LB fetch failed for mbid=\(mbid, privacy: .public)")
            return []
        }

        // Enrich with inLibrary flag using name-based lookup against the local artist index
        let limited = Array(dtos.prefix(limit))
        var results: [SimilarArtistRecommendation] = []
        results.reserveCapacity(limited.count)

        for dto in limited {
            if let libraryArtist = await libraryService.findArtist(byName: dto.name) {
                results.append(SimilarArtistRecommendation(
                    id: libraryArtist.id,
                    name: dto.name,
                    coverArt: libraryArtist.coverArt,
                    inLibrary: true,
                    mbid: dto.artistMbid
                ))
            } else {
                results.append(SimilarArtistRecommendation(
                    id: dto.artistMbid,
                    name: dto.name,
                    coverArt: nil,
                    inLibrary: false,
                    mbid: dto.artistMbid
                ))
            }
        }

        let inLibraryCount = results.filter { $0.inLibrary }.count
        Logger.listenBrainz.debug("similarArtists: \(results.count, privacy: .public) results (\(inLibraryCount, privacy: .public) in library) for mbid=\(mbid, privacy: .public)")
        return results
    }
}
