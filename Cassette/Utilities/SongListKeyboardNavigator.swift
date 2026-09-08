// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit
import Carbon.HIToolbox
import OSLog
import SwiftUI

/// Keyboard navigation for song-list pages (All Songs, playlist detail).
///
/// SwiftUI offers no API to give a `List` keyboard focus programmatically, so arrow keys would
/// only reach the list after the user clicks it. Instead, a page REGISTERS itself here while
/// visible — providing its songs, selection binding, scroll proxy and play action — and the
/// app-level `KeyboardInterceptor` forwards bare ↑ / ↓ / ↩ to the active registration. The
/// selection is driven through the binding, so the List renders its native highlight and the
/// arrows work immediately on page switch, with no click required.
@MainActor
final class SongListKeyboardNavigator {
    static let shared = SongListKeyboardNavigator()

    struct Registration {
        let id = UUID()
        /// Live accessor — read on every keypress so reloads never go stale.
        let songs: () -> [DisplayableSong]
        let selection: Binding<String?>
        let scrollTo: (String) -> Void
        let play: (Int) -> Void
    }

    private var registration: Registration?

    /// TEMP-DEBUG 实验3：置 true 时 handleKeyDown 对所有键返回 false
    static var disableNavigator = false

    private static let logger = Logger(subsystem: "app.cassette", category: "SongListNav")

    private init() {}

    /// Registers the visible page. Returns a token to pass to `deactivate` — a page that
    /// disappears must not clear a newer page's registration (appear/disappear can interleave
    /// during transitions).
    func activate(
        songs: @escaping () -> [DisplayableSong],
        selection: Binding<String?>,
        scrollTo: @escaping (String) -> Void,
        play: @escaping (Int) -> Void
    ) -> UUID {
        let registration = Registration(
            songs: songs,
            selection: selection,
            scrollTo: scrollTo,
            play: play
        )
        self.registration = registration
        Self.logger.notice("SongListNavigator activated (\(registration.id.uuidString.prefix(8), privacy: .public))")
        return registration.id
    }

    func deactivate(_ token: UUID) {
        if registration?.id == token {
            registration = nil
            Self.logger.notice("SongListNavigator deactivated")
        }
    }

    /// Returns true when the key was consumed by the active registration.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        if Self.disableNavigator {
            Self.logger.notice("NAVIGATOR DISABLED — key \(event.keyCode) passes")
            return false
        }
        guard let registration else { return false }
        switch event.keyCode {
        case UInt16(kVK_DownArrow):
            move(registration, +1)
            return true
        case UInt16(kVK_UpArrow):
            move(registration, -1)
            return true
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            playSelected(registration)
            return true
        default:
            return false
        }
    }

    private func move(_ registration: Registration, _ delta: Int) {
        let songs = registration.songs()
        Self.logger.debug("move \(delta, privacy: .public): \(songs.count) songs, current=\(registration.selection.wrappedValue ?? "nil", privacy: .public)")
        guard !songs.isEmpty else { return }
        let current = registration.selection.wrappedValue.flatMap { id in
            songs.firstIndex { $0.id == id }
        }
        let next: Int
        switch current {
        case .none: next = delta > 0 ? 0 : songs.count - 1
        case .some(let index): next = min(max(index + delta, 0), songs.count - 1)
        }
        let id = songs[next].id
        registration.selection.wrappedValue = id
        registration.scrollTo(id)
    }

    private func playSelected(_ registration: Registration) {
        guard let id = registration.selection.wrappedValue,
              let index = registration.songs().firstIndex(where: { $0.id == id }) else { return }
        registration.play(index)
    }
}
