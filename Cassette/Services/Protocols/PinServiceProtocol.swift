// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation

@MainActor
protocol PinServiceProtocol: AnyObject {
    func pin(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID
    )
    func unpin(itemType: PinnedItemType, itemId: String)
    func isPinned(itemType: PinnedItemType, itemId: String) -> Bool
    func reorder(items: [PinnedItem])
    func currentPinnedCount() -> Int
    /// Updates the stored cover art ID for a pinned item. No-op if not pinned.
    func updateCoverArtId(itemType: PinnedItemType, itemId: String, newCoverArtId: String?)
    /// 重命名固定项的显示名（本地 SwiftData）。
    func renamePinnedItem(itemType: PinnedItemType, itemId: String, newName: String)
}
