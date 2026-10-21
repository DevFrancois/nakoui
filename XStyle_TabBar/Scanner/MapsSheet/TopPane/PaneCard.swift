//
//  PaneCard.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Editable top-pane content, filling the entire rounded surface with the placeholder gradient.
/// PaneSurface owns the corners; TopPaneView owns positioning and collapse effects.
struct PaneCard: View {
    var body: some View {
        PanePalette.gradient
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Expanded", traits: .sizeThatFitsLayout) {
    PaneCardPreview(height: 360)
}

#Preview("Compact · Dark", traits: .sizeThatFitsLayout) {
    PaneCardPreview(height: 132)
        .preferredColorScheme(.dark)
}

#Preview("Narrow", traits: .sizeThatFitsLayout) {
    PaneCardPreview(width: 304, height: 300)
}

private struct PaneCardPreview: View {
    var width: CGFloat = 377
    var height: CGFloat

    var body: some View {
        PaneSurface(sheetCornerRadius: 36) {
            PaneCard()
        }
        .frame(width: width, height: height)
        .padding(8)
        .background(Color(.systemGroupedBackground))
    }
}
#endif
