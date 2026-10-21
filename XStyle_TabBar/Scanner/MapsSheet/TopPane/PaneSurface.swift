//
//  PaneSurface.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded card surface. Never glass: the collapse effects rasterize the pane offscreen.
struct PaneSurface<Content: View>: View {
    var sheetCornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: sheetCornerRadius, style: .continuous))
    }
}

#if DEBUG
#Preview("Rounded Surface", traits: .sizeThatFitsLayout) {
    PaneSurface(sheetCornerRadius: 36) {
        ScannerBackdropPlaceholder()
    }
    .frame(width: 377, height: 220)
    .padding(8)
    .background(Color(.systemGroupedBackground))
}
#endif
