//
//  PaneSurface.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded card surface, with continuous corners, and a faint edge in dark
/// mode, where dark content would melt into the background.
struct PaneSurface<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay {
                if colorScheme == .dark {
                    shape.strokeBorder(.white.opacity(PaneMetrics.darkEdgeOpacity), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
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
