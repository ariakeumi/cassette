// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct CassetteCommands: Commands {
    var body: some Commands {
        CommandMenu("Playback") {
            // No keyboardShortcut here: Space is intercepted app-wide by KeyboardInterceptor
            // (a menu binding would double-fire or lose to focused lists).

            Divider()

            Button("Next Track") {
                NotificationCenter.default.post(name: .cassetteSkipNext, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                NotificationCenter.default.post(name: .cassetteSkipPrevious, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Toggle Shuffle") {
                NotificationCenter.default.post(name: .cassetteToggleShuffle, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Toggle Repeat") {
                NotificationCenter.default.post(name: .cassetteToggleRepeat, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Show Queue") {
                NotificationCenter.default.post(name: .cassetteToggleQueue, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Volume Up") {
                NotificationCenter.default.post(name: .cassetteVolumeUp, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") {
                NotificationCenter.default.post(name: .cassetteVolumeDown, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Go to Home") {
                NotificationCenter.default.post(name: .cassetteSelectHome, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Search") {
                NotificationCenter.default.post(name: .cassetteFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Go to Songs") {
                NotificationCenter.default.post(name: .cassetteSelectSongs, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Toggle Lyrics") {
                NotificationCenter.default.post(name: .cassetteToggleLyrics, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Toggle Full Screen") {
                NotificationCenter.default.post(name: .cassetteToggleFullScreen, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
