// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import AppKit

enum ExternalLinkOpener {
    /// Opens a URL in the system browser.
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

}
