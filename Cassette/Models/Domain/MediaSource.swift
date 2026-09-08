// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum MediaSource: Sendable {
    case downloaded(URL)
    case cached(URL)
    /// Remote stream of a finite-duration song. Custom headers must be injected
    /// into every request to reach Cloudflare-protected (or other reverse-proxy) hosts.
    case stream(URL, customHeaders: [String: String])
    var url: URL {
        switch self {
        case .downloaded(let url), .cached(let url):
            return url
        case .stream(let url, _):
            return url
        }
    }

    var customHeaders: [String: String] {
        switch self {
        case .downloaded, .cached:
            return [:]
        case .stream(_, let headers):
            return headers
        }
    }
}
