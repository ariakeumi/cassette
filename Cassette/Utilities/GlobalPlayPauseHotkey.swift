// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Carbon.HIToolbox
import AppKit

/// A user-configurable system-wide hotkey for Play/Pause, persisted in UserDefaults.
/// `keyCode` is a Carbon virtual key code and `carbonModifiers` a Carbon modifier mask — the exact
/// representation `RegisterEventHotKey` takes. `display` is generated at record time from the
/// captured NSEvent (e.g. "⌘⌥P") so special keys read naturally.
nonisolated struct GlobalPlayPauseHotkey: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    private static let storageKey = "cassette.globalPlayPauseHotkey"

    static func load() -> GlobalPlayPauseHotkey? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(GlobalPlayPauseHotkey.self, from: data)
    }

    static func save(_ hotkey: GlobalPlayPauseHotkey?) {
        if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    /// Builds a hotkey from a recorded key event, or nil when it can't be a global hotkey —
    /// a bare key with no ⌘/⌥/⌃/fn modifier would swallow the keystroke system-wide.
    static func from(event: NSEvent) -> GlobalPlayPauseHotkey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = UInt32(event.keyCode)
        let significant = flags.subtracting([.shift, .capsLock, .function])
        let hasFunctionKey = flags.contains(.function) && isFunctionKeyCode(keyCode)
        guard !significant.isEmpty || hasFunctionKey else { return nil }

        let carbonModifiers = carbonFlags(from: flags)
        let display = Self.displayString(keyCode: keyCode, flags: flags, characters: event.charactersIgnoringModifiers)
        return GlobalPlayPauseHotkey(keyCode: keyCode, carbonModifiers: carbonModifiers, display: display)
    }

    private static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private static func isFunctionKeyCode(_ keyCode: UInt32) -> Bool {
        Self.specialKeyNames[keyCode] != nil
    }

    private static func displayString(keyCode: UInt32, flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }

        let keyName = specialKeyNames[keyCode]
            ?? characters.flatMap { $0.isEmpty ? nil : $0.uppercased() }
            ?? "Key \(keyCode)"
        return symbols + keyName
    }

    /// Human-readable names for keys that have no character representation.
    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "esc",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19",
    ]
}
