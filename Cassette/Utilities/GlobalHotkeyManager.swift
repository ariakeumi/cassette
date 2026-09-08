// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Carbon.HIToolbox
import Foundation

/// Registers the user's global Play/Pause hotkey via Carbon's RegisterEventHotKey so it fires
/// system-wide — even when Cassette is not the active app. On fire it posts
/// `.cassetteTogglePlayPause`, which the root view's notification wiring routes to the player.
///
/// Only one hotkey is ever registered, so the event handler doesn't need to disambiguate.
nonisolated final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let hotkeyId = EventHotKeyID(signature: OSType(0x4341_5354) /* 'CAST' */, id: 1)
    private static let eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    /// The C-convention handler must not capture context; posting the notification directly is
    /// enough since there is exactly one registered hotkey. NotificationCenter.post is thread-safe.
    private static let handler: EventHandlerUPP = { _, _, _ in
        NotificationCenter.default.post(name: .cassetteTogglePlayPause, object: nil)
        return noErr
    }

    private init() {}

    /// Registers `hotkey` system-wide, replacing any previous registration. `nil` unregisters.
    /// Returns false when macOS rejected the registration (shortcut owned by another app).
    @discardableResult
    func apply(_ hotkey: GlobalPlayPauseHotkey?) -> Bool {
        unregister()

        guard let hotkey else { return true }

        if handlerRef == nil {
            var eventType = Self.eventType
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.handler,
                1,
                &eventType,
                nil,
                &handlerRef
            )
            guard status == noErr else { return false }
        }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            Self.hotkeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return false }
        hotkeyRef = ref
        return true
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRef = nil
    }
}
