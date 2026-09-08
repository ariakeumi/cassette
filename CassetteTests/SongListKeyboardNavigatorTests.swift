// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit
import SwiftSonic
import SwiftUI
import Testing
@testable import Cassette

/// Exercises the selection math and key routing of SongListKeyboardNavigator with synthetic
/// key events. The NSEvent monitor wiring itself is app-level and not covered here.
@MainActor
struct SongListKeyboardNavigatorTests {

    /// DisplayableSong has no memberwise init and Song is Decodable — JSON decoding is the
    /// least-typed fixture path.
    private func makeSong(_ index: Int) -> DisplayableSong {
        let json = "{\"id\":\"song-\(index)\",\"title\":\"T\(index)\",\"isDir\":false}"
        let song = try! JSONDecoder().decode(Song.self, from: Data(json.utf8))
        return DisplayableSong(from: song)
    }

    private var songs: [DisplayableSong] { (0..<5).map(makeSong) }

    private func keyDown(_ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        )!
    }

    @Test("down moves selection from none to first, then forward; up goes back; ↩ plays selection")
    func navigationFlow() {
        let navigator = SongListKeyboardNavigator.shared
        var selection: String?
        var scrolledTo: String?
        var playedIndex: Int?

        let token = navigator.activate(
            songs: { songs },
            selection: Binding(get: { selection }, set: { selection = $0 }),
            scrollTo: { scrolledTo = $0 },
            play: { playedIndex = $0 }
        )
        defer { navigator.deactivate(token) }

        #expect(navigator.handleKeyDown(keyDown(125))) // ↓ → first row
        #expect(selection == "song-0")
        #expect(scrolledTo == "song-0")

        #expect(navigator.handleKeyDown(keyDown(125))) // ↓ → second row
        #expect(selection == "song-1")

        #expect(navigator.handleKeyDown(keyDown(126))) // ↑ → back to first row
        #expect(selection == "song-0")

        #expect(navigator.handleKeyDown(keyDown(36))) // ↩ plays the selected row
        #expect(playedIndex == 0)
    }

    @Test("selection clamps at both ends and unregistered pages consume nothing")
    func clampingAndGating() {
        let navigator = SongListKeyboardNavigator.shared
        var selection: String? = "song-0"
        let token = navigator.activate(
            songs: { songs },
            selection: Binding(get: { selection }, set: { selection = $0 }),
            scrollTo: { _ in },
            play: { _ in }
        )
        defer { navigator.deactivate(token) }

        #expect(navigator.handleKeyDown(keyDown(126))) // ↑ at the top → stays
        #expect(selection == "song-0")

        selection = "song-4"
        #expect(navigator.handleKeyDown(keyDown(125))) // ↓ at the bottom → stays
        #expect(selection == "song-4")

        navigator.deactivate(token)
        #expect(!navigator.handleKeyDown(keyDown(125))) // unregistered → not consumed
    }
}
