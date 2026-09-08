// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit
import SwiftSonic
import SwiftUI
import Testing
@testable import Cassette

/// End-to-end check of the app-level interception chain with a REAL NSWindow: register a song
/// list, synthesize a ↓ keyDown targeting that window, and confirm `KeyboardInterceptor.intercept`
/// consumes it and moves the selection. Reproduces the "arrows beep / do nothing" failure mode.
@MainActor
struct KeyboardInterceptorTests {

    private func makeSong(_ index: Int) -> DisplayableSong {
        let json = "{\"id\":\"song-\(index)\",\"title\":\"T\(index)\",\"isDir\":false}"
        let song = try! JSONDecoder().decode(Song.self, from: Data(json.utf8))
        return DisplayableSong(from: song)
    }

    private func arrowKeyDown(_ keyCode: UInt16, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        )!
    }

    @Test("intercept consumes ↓ and moves the registered selection")
    func downArrowMovesSelection() {
        let songs = (0..<5).map(makeSong)
        var selection: String?
        var playedIndex: Int?

        let navigator = SongListKeyboardNavigator.shared
        let token = navigator.activate(
            songs: { songs },
            selection: Binding(get: { selection }, set: { selection = $0 }),
            scrollTo: { _ in },
            play: { playedIndex = $0 }
        )
        defer { navigator.deactivate(token) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.makeKeyAndOrderFront(nil)

        let event = arrowKeyDown(125, window: window) // ↓
        let result = KeyboardInterceptor.intercept(event, keyWindow: window)

        #expect(result == nil, "↓ should be consumed by the registered song list")
        #expect(selection == "song-0", "↓ should select the first song")

        let event2 = arrowKeyDown(125, window: window)
        _ = KeyboardInterceptor.intercept(event2, keyWindow: window)
        #expect(selection == "song-1")

        let event3 = arrowKeyDown(36, window: window) // ↩
        _ = KeyboardInterceptor.intercept(event3, keyWindow: window)
        #expect(playedIndex == 1)

        window.orderOut(nil)
        navigator.deactivate(token)
    }

    @Test("↓ is consumed even when keyWindow is nil (SwiftUI transient state)")
    func nilKeyWindowStillNavigates() {
        let songs = (0..<5).map(makeSong)
        var selection: String?
        let navigator = SongListKeyboardNavigator.shared
        let token = navigator.activate(
            songs: { songs },
            selection: Binding(get: { selection }, set: { selection = $0 }),
            scrollTo: { _ in },
            play: { _ in }
        )
        defer { navigator.deactivate(token) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.makeKeyAndOrderFront(nil)

        let event = arrowKeyDown(125, window: window) // ↓
        let result = KeyboardInterceptor.intercept(event, keyWindow: nil)
        #expect(result == nil, "nil keyWindow must not skip the navigator")
        #expect(selection == "song-0")
        window.orderOut(nil)
    }

    @Test("modified keys pass through untouched")
    func modifiedKeysPassThrough() {
        let songs = (0..<3).map(makeSong)
        var selection: String?
        let navigator = SongListKeyboardNavigator.shared
        let token = navigator.activate(
            songs: { songs },
            selection: Binding(get: { selection }, set: { selection = $0 }),
            scrollTo: { _ in },
            play: { _ in }
        )
        defer { navigator.deactivate(token) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        let cmdDown = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "↓", charactersIgnoringModifiers: "↓",
            isARepeat: false, keyCode: 125
        )!
        let result = KeyboardInterceptor.intercept(cmdDown, keyWindow: window)
        #expect(result != nil, "⌘↓ belongs to the volume shortcut — must not be consumed")
        #expect(selection == nil)
        window.orderOut(nil)
    }
}
