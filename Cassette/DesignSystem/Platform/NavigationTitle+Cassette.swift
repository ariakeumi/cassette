// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Sets navigation title display mode to inline. No-op on macOS where the concept doesn't exist.
    func navigationBarTitleDisplayModeInline() -> some View {
        self
    }

    /// Sets navigation title display mode to large. No-op on macOS where the concept doesn't exist.
    func navigationBarTitleDisplayModeLarge() -> some View {
        self
    }
}
