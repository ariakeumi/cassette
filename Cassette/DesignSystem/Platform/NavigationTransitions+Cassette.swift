// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

extension View {
    /// No-op on macOS (the zoom navigation transition API is unavailable); kept for call-site compatibility.
    @ViewBuilder
    func cassetteZoomTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        self
    }

    /// Marks this view as the matched transition source for a zoom navigation.
    /// No-op when either parameter is nil.
    @ViewBuilder
    func cassetteMatchedTransitionSource(id: String?, in namespace: Namespace.ID?) -> some View {
        self
    }
}
