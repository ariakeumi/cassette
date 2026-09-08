// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Playlist cover thumbnail for the library surfaces — a raster `CoverArtView` at the standard
/// continuous-corner radius.
struct PlaylistCoverThumbnail: View {
    let coverArtId: String
    let size: CGFloat

    var body: some View {
        CoverArtView(id: coverArtId, size: Int(size * 2))
            .frame(width: size, height: size)
            .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
    }
}
