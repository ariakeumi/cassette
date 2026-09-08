// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit
import OSLog

/// Views that need raw key events (e.g. the global-hotkey recorder) conform to opt out of the
/// app-level interception in `KeyboardInterceptor`.
nonisolated protocol ConsumesRawKeys: NSView {}

/// App-level key interception, installed before SwiftUI dispatch:
///
/// - **Space** → Play/Pause. A menu binding can't do this reliably: a focused List/NSTableView
///   swallows Space for scrolling. The monitor consumes it so it works everywhere.
/// - **↑ / ↓ / ↩** → forwarded to `SongListKeyboardNavigator` when a song-list page (All Songs,
///   playlist detail) is active, so keyboard navigation works immediately on page switch.
///
/// - **⌘1…9** → jump to the nth pinned playlist (routed before the first-responder gates).
/// - **⌘D** → Home. Same gate ordering as ⌘1…9: with the search field focused, the editable-
///   NSTextView pass-through would let the event reach the field's performKeyEquivalent
///   (which drops it). The menu binding in CassetteCommands stays for discoverability —
///   the monitor consumes the key first, so the two paths can never double-fire.
///
/// Keystrokes that belong to text editing (or to views declared as `ConsumesRawKeys`) pass
/// through untouched; modified keys (⌘↑ volume, ⌘F search, …) are left to the menu shortcuts.
enum KeyboardInterceptor {
    private static let spaceKeyCode: UInt16 = 49
    private static let logger = Logger(subsystem: "app.cassette", category: "KeyInterceptor")
    // TEMP-DEBUG: 实验观察埋点（keyWindow / firstResponder / 消费路径），稳定后移除
    private static let dbg = Logger(subsystem: "app.cassette", category: "KeyDebug")

    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // TEMP-DIAG 实验：local monitor 最入口 — 记录每一个真实/合成 keyDown
            let frDesc: String
            if let kw = NSApp.keyWindow, let fr = kw.firstResponder {
                frDesc = String(describing: type(of: fr))
            } else {
                frDesc = "nil"
            }
            dbg.notice("""
            ========== REAL KEY EVENT ==========
            pid=\(ProcessInfo.processInfo.processIdentifier)
            bundlePath=\(Bundle.main.bundlePath, privacy: .public)
            keyCode=\(event.keyCode)
            characters='\(event.characters ?? "nil", privacy: .public)'
            charactersIgnoringModifiers='\(event.charactersIgnoringModifiers ?? "nil", privacy: .public)'
            modifierFlags=\(String(describing: event.modifierFlags), privacy: .public)
            event.window=\(String(describing: event.window?.title), privacy: .public)
            keyWindow=\(String(describing: NSApp.keyWindow?.title), privacy: .public)
            mainWindow=\(String(describing: NSApp.mainWindow?.title), privacy: .public)
            firstResponder=\(frDesc, privacy: .public)
            =====================================
            """)
            let keyWindow = NSApp.keyWindow ?? event.window ?? NSApp.mainWindow
            return intercept(event, keyWindow: keyWindow)
        }
    }

    /// The interception decision, split out of the monitor closure so tests can drive it with
    /// synthetic events. Returns `nil` when the event is consumed.
    static func intercept(_ event: NSEvent, keyWindow: NSWindow?) -> NSEvent? {
        // TEMP-DIAG 诊断2/4：firstResponder 全类名 + keyWindow 详查
        let frDesc: String
        if let fr = keyWindow?.firstResponder {
            frDesc = String(describing: type(of: fr))
        } else {
            frDesc = "nil"
        }
        logger.notice("DIAG keyDown keyCode=\(event.keyCode) keyWindow=\(String(describing: keyWindow?.title), privacy: .public) isActive=\(NSApp.isActive, privacy: .public) firstResponderClass=\(frDesc, privacy: .public)")

        let firstResponder = keyWindow?.firstResponder

        // ⌘1…9 → jump to the nth pinned playlist. MUST run before the first-responder gates:
        // with the search field focused, the editable-NSTextView pass-through below would let the
        // event reach the field's performKeyEquivalent (which drops it). ⌘+digit is a chord, never
        // text input, so intercepting it while a text field is focused is always safe.
        if event.keyCode >= 18 && event.keyCode <= 27,
           event.modifierFlags.contains(.command) {
            let digit = event.keyCode == 27 ? 0 : Int(event.keyCode - 18 + 1) // keyCode 27 = '0'
            guard digit >= 1 else { return event }
            NotificationCenter.default.post(
                name: .cassetteOpenPinnedPlaylist,
                object: nil,
                userInfo: ["index": digit - 1]
            )
            return nil
        }

        // ⌘D → Home. Same rationale as ⌘1…9 above: a chord, never text input, safe to
        // intercept while a text field is focused. Pure ⌘ only — ⌘⌥D / ⌘⇧D stay untouched.
        if event.keyCode == 2, // D
           event.modifierFlags.intersection(.deviceIndependentFlagsMask)
               .subtracting([.shift, .capsLock, .function, .numericPad]) == [.command] {
            NotificationCenter.default.post(name: .cassetteSelectHome, object: nil)
            return nil
        }

        // ⌃⌘F → toggle fullscreen. This macOS release ships no "Enter Full Screen" item in the
        // Window menu for the app, so the default chord is unbound — route it here (same gate
        // ordering as ⌘1…9/⌘D: chords must not reach the focused text field). The menu binding
        // in CassetteCommands stays for discoverability; the monitor consumes first, so the two
        // paths can never double-fire. Main window preferred: the mini-player panel can never
        // become main, so it is only used when no main window exists.
        if event.keyCode == 3, // F
           event.modifierFlags.intersection(.deviceIndependentFlagsMask)
               .subtracting([.shift, .capsLock, .function, .numericPad]) == [.command, .control] {
            (NSApp.mainWindow ?? keyWindow)?.toggleFullScreen(nil)
            return nil
        }

        // Controls that own their keyboard behaviour always pass through.
        if let textView = firstResponder as? NSTextView, textView.isEditable {
            return event // typing in a text field
        }
        if firstResponder is ConsumesRawKeys {
            return event // views that capture keys themselves (hotkey recorder)
        }
        if firstResponder is NSButton {
            return event // focused buttons (alert default buttons etc.) handle their own keys
        }

        // Only bare keys are intercepted — modified keys belong to text editing and menu shortcuts.
        // NOTE: real-hardware arrow keys carry .numericPad AND .function modifier flags; both must be
        // subtracted or every physical ↓/↑ is misread as a modified combo and passed through (beep).
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.shift, .capsLock, .function, .numericPad])
        guard modifiers.isEmpty else { return event }

        if event.keyCode == spaceKeyCode {
            NotificationCenter.default.post(name: .cassetteTogglePlayPause, object: nil)
            return nil // consume — never scrolls the focused list
        }

        // A sheet attached to either the key or the main window is modal and owns the keyboard.
        if keyWindow?.attachedSheet != nil || NSApp.mainWindow?.attachedSheet != nil {
            return event
        }


        // ↑ / ↓ / ↩ drive the registered song list. Runs even when keyWindow is transiently nil —
        // consuming here is what keeps the sidebar List from reacting to bare arrows.
        let handled = SongListKeyboardNavigator.shared.handleKeyDown(event)
        if handled {
            return nil
        }
        return event
    }
}
