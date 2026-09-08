// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Centralized haptic feedback catalog.
///
/// Usage: `HapticFeedback.medium.trigger()`
///
/// Catalog:
/// - `.light`     — navigation, skip prev/next, toggle shuffle/repeat, secondary toggles
/// - `.medium`    — play/pause, swipe MiniPlayer, play album/playlist, QueueView skip
/// - `.heavy`     — destructive confirmations (trash download, remove all)
/// - `.selection` — continuous selection change (alphabet jump bar drag, pickers)
/// - `.success`   — download complete, pin to home
/// - `.warning`   — limit reached (max pinned, offline action)
/// - `.error`     — download failed, sync failed, playback failed
@MainActor
enum HapticFeedback {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error

    func trigger() {
    }
}
