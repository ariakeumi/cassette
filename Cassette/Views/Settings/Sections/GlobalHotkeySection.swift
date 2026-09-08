// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit
import Carbon.HIToolbox
import OSLog
import SwiftUI

/// Settings section for the system-wide Play/Pause hotkey. The hotkey fires even when Cassette
/// is not the active app; it is registered through Carbon and routed to the player via the same
/// `.cassetteTogglePlayPause` notification the in-app wiring uses.
struct GlobalHotkeySection: View {
    @State private var hotkey: GlobalPlayPauseHotkey? = GlobalPlayPauseHotkey.load()
    @State private var isRecording = false
    @State private var registrationFailed = false

    var body: some View {
        Section {
            HStack {
                Text("Play / Pause")
                Spacer()
                HotkeyRecorderView(
                    display: hotkey?.display ?? "",
                    isRecording: isRecording,
                    onRecord: { setHotkey($0) },
                    onCancel: { isRecording = false }
                )
                .frame(width: 150, height: 24)

                if hotkey != nil {
                    Button("Clear") { setHotkey(nil) }
                        .buttonStyle(.borderless)
                }
            }
            .buttonStyle(.borderless)

            if isRecording {
                Label("Press the new key combination… (esc to cancel)", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if registrationFailed {
                Label("Registration failed — the shortcut may already be taken by another app.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Global Hotkey")
        } footer: {
            Text("The Play / Pause shortcut works system-wide, even when Cassette is not the active app.")
        }
    }

    private func setHotkey(_ newHotkey: GlobalPlayPauseHotkey?) {
        isRecording = false
        registrationFailed = false
        if GlobalHotkeyManager.shared.apply(newHotkey) {
            GlobalPlayPauseHotkey.save(newHotkey)
            hotkey = newHotkey
        } else {
            registrationFailed = true
        }
    }
}

/// SwiftUI wrapper for the AppKit key-capture field.
private struct HotkeyRecorderView: NSViewRepresentable {
    let display: String
    let isRecording: Bool
    let onRecord: (GlobalPlayPauseHotkey?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.onRecord = onRecord
        field.onCancel = onCancel
        return field
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.displayText = isRecording ? "Recording…" : (display.isEmpty ? "Record Shortcut" : display)
        field.isRecording = isRecording
        field.onRecord = onRecord
        field.onCancel = onCancel
    }
}

/// Click-to-arm key capture field. While armed, keyDown records the pressed combination;
/// escape cancels. Combinations without ⌘/⌥/⌃/fn are ignored (they can't be global hotkeys).
final class HotkeyRecorderField: NSView, ConsumesRawKeys {
    var displayText: String = "" { didSet { needsDisplay = true } }
    var isRecording: Bool = false { didSet { needsDisplay = true } }
    var onRecord: ((GlobalPlayPauseHotkey?) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // TEMP-DEBUG 实验2：确认该 responder 是否收到 keyDown
        Logger(subsystem: "app.cassette", category: "KeyDebug").notice("HotkeyRecorderField.keyDown keyCode=\(event.keyCode)")
        if event.keyCode == UInt32(kVK_Escape) {
            onCancel?()
            return
        }
        if let hotkey = GlobalPlayPauseHotkey.from(event: event) {
            onRecord?(hotkey)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let isFocused = window?.firstResponder === self
        let background: NSColor
        if isRecording {
            background = .selectedTextBackgroundColor
        } else if isFocused {
            background = .controlAccentColor.withAlphaComponent(0.15)
        } else {
            background = .controlBackgroundColor
        }
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()

        let border: NSColor = isRecording || isFocused ? .controlAccentColor : .separatorColor
        border.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let text: NSString = displayText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
}
