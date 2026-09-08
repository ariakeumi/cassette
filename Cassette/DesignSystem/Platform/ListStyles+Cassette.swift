// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// Uses the native macOS inset list style.
    func cassetteSheetListStyle() -> some View {
        self.listStyle(.inset)
    }
}
