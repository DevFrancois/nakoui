//
//  PaneSurface.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded card surface, with continuous corners.
struct PaneSurface<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

#if DEBUG
#Preview("Rounded Surface", traits: .sizeThatFitsLayout) {
    PaneSurface(cornerRadius: PaneMetrics.viewportCornerRadius) {
        ScannerBackdropPlaceholder()
    }
    .frame(width: 377, height: 220)
    .padding(8)
    .background(Color(.systemGroupedBackground))
}
#endif
