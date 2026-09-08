// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum SidebarSection: String, Hashable, Identifiable, CaseIterable {
    case home
    case albums
    case artists
    case songs
    case playlists
    case favorites

    var id: String { rawValue }

    var displayLabel: String {
        // String(localized:) 走 Localizable.xcstrings 查找；直接返回字面量不会本地化
        switch self {
        case .home:      return String(localized: "Home")
        case .albums:    return String(localized: "Albums")
        case .artists:   return String(localized: "Artists")
        case .songs:     return String(localized: "Songs")
        case .playlists: return String(localized: "Playlists")
        case .favorites: return String(localized: "Favorites")
        }
    }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .albums:    return "square.stack"
        case .artists:   return "music.mic"
        case .songs:     return "music.note"
        case .playlists: return "music.note.list"
        case .favorites: return "star"
        }
    }
}

nonisolated enum SidebarDestination: Hashable {
    case section(SidebarSection)
    case pinned(String) // PinnedItem.id — "{type}:{itemId}"
}
