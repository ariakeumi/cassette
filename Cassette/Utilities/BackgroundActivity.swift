// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

/// Runs a long piece of work to completion after the user moves on.
///
/// On macOS apps are not suspended on losing focus, so this is a plain passthrough; the wrapper
/// documents the intent (long-running work that must finish) and keeps call sites uniform.
nonisolated enum BackgroundActivity {


    /// Runs `operation` inside a background task assertion. A no-op on macOS, where apps are not
    /// suspended on losing focus.
    static func run<T: Sendable>(_ name: String, operation: @Sendable () async -> T) async -> T {
        return await operation()
    }
}
