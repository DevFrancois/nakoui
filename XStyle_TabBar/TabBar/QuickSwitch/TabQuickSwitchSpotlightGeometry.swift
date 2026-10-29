import CoreGraphics

/// The circle enclosing the active area. Rendering pads and blurs the mask
/// with the original spotlight feather.
/// List callers supply their visible card, never the scrolling rows' bounds.
struct TabQuickSwitchSpotlightGeometry: Equatable {
    let center: CGPoint
    let radius: CGFloat

    static func resolve(focus: CGRect) -> Self {
        Self(center: CGPoint(x: focus.midX, y: focus.midY), radius: hypot(focus.width, focus.height) / 2)
    }
}
