// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AppKit

extension PlatformImage {
    /// Returns a copy scaled down so neither dimension exceeds maxDimension.
    /// Returns self unchanged if already within bounds.
    nonisolated func resized(maxDimension: CGFloat) -> PlatformImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let result = NSImage(size: newSize)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// JPEG-encodes the receiver at the given quality (0.0–1.0).
    nonisolated func jpgData(quality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
