import SwiftUI

/// Unfurls the already-clipped viewport with Wave. A projection keeps the
/// native camera layer live; a distortion shader cannot sample that layer.
struct ScannerViewportAppearance: ViewModifier {
    var entrance: ScannerViewportEntrance?
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var viewportOrigin = CGPoint.zero

    func body(content: Content) -> some View {
        let progress = reduceMotion ? 1 : entrance?.progress ?? 1
        let source = entrance?.sourcePoint.map {
            CGPoint(x: $0.x - viewportOrigin.x, y: $0.y - viewportOrigin.y)
        }
        content
            .modifier(ScannerViewportWarp(progress: progress, source: source,
                                          isRightToLeft: layoutDirection == .rightToLeft))
            // Match the reference's blur after distortion, clearing as we open.
            .blur(radius: 8 * (1 - min(max(progress, 0), 1)))
            .opacity(min(max(progress * 5, 0), 1))
            .background {
                // A sibling of the projected content, so measuring the origin
                // never feeds the animated transform back into itself.
                Color.clear
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        proxy.frame(in: .global).origin
                    } action: { origin in
                        viewportOrigin = origin
                    }
            }
            .allowsHitTesting(progress >= 0.92)
            .accessibilityHidden(progress < 0.92)
            .onChange(of: isActive && scenePhase == .active, initial: true) {
                updateEntrance()
            }
            .onChange(of: reduceMotion) {
                updateEntrance()
            }
            .onDisappear {
                entrance?.finish()
            }
    }

    private func updateEntrance() {
        entrance?.update(isActive: isActive && scenePhase == .active, reduceMotion: reduceMotion)
    }
}

/// Wave supplies every frame, so no second SwiftUI interpolation is needed.
private nonisolated struct ScannerViewportWarp: GeometryEffect {
    var progress: CGFloat
    var source: CGPoint?
    var isRightToLeft: Bool

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard progress != 1, size.width > 0, size.height > 0 else {
            return ProjectionTransform()
        }
        let origin = source ?? CGPoint(x: size.width * (isRightToLeft ? 0.6 : 0.4), y: size.height + 48)
        return QuadWarpEffect(quad: ScannerViewportGeometry.quad(in: size, progress: progress, source: origin))
            .effectValue(size: size)
    }
}

nonisolated enum ScannerViewportGeometry {
    /// Opens upward from a small seed at the Scan icon. The upper edge fans
    /// out ahead of the lower edge, which stays pinched toward the icon.
    /// Keep Wave's small overshoot, while bounding the projection away from a
    /// degenerate quad. Coordinates adapt to the pane's current layout.
    static func quad(in size: CGSize, progress: CGFloat, source: CGPoint) -> Quad {
        let remaining = 1 - min(max(progress, 0), 1.04)
        // A tiny, non-degenerate trapezoid keeps the projection well-defined.
        // The delayed bottom edge supplies the mesh-like unfurl, rather than
        // making the entire camera simply scale up from the toolbar.
        let topRemaining = remaining * abs(remaining)
        let top = (source.y - 28) * remaining
        let bottom = size.height + (source.y - size.height) * remaining
        return Quad(
            topLeft: CGPoint(x: (source.x - 22) * topRemaining, y: top),
            topRight: CGPoint(x: size.width + (source.x + 22 - size.width) * topRemaining, y: top),
            bottomRight: CGPoint(x: size.width + (source.x + 13 - size.width) * remaining, y: bottom),
            bottomLeft: CGPoint(x: (source.x - 13) * remaining, y: bottom)
        )
    }
}

#Preview("Viewport entrance · Wave") {
    ScannerViewportEntrancePreview()
}

private struct ScannerViewportEntrancePreview: View {
    @State private var entrance = ScannerViewportEntrance()

    var body: some View {
        VStack(spacing: 24) {
            PaneSurface(cornerRadius: PaneMetrics.viewportCornerRadius) {
                ScannerBackdropPlaceholder()
                    .overlay { ScannerViewfinder() }
            }
            .modifier(ScannerViewportAppearance(entrance: entrance, isActive: true))
            .id(ObjectIdentifier(entrance))

            Button("Replay entrance") {
                entrance.finish()
                entrance = ScannerViewportEntrance()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
