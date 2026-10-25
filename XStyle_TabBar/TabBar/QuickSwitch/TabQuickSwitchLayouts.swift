import SwiftUI

/// Places a held tab's list card past the bar, as wide as its widest row
/// where there's room, and as tall as its rows at that width where there's
/// room; see `TabQuickSwitchPlacement.listFrame`. Fills the overlay, whose
/// space the frames are in.
struct TabQuickSwitchListLayout: Layout {
    var tab: CGRect
    var bar: CGRect
    var area: CGRect
    var axis: Axis

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            // Narrower than its rows' one line, the rows wrap and grow.
            let width = min(subview.sizeThatFits(.unspecified).width, area.width)
            let frame = TabQuickSwitchPlacement.listFrame(
                size: subview.sizeThatFits(ProposedViewSize(width: width, height: nil)), tab: tab, bar: bar,
                area: area, axis: axis, spacing: TabQuickSwitchMetrics.spacing
            )
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// Marks the fan's label, which names the bubble under the finger.
nonisolated struct TabQuickSwitchFanLabel: LayoutValueKey {
    static let defaultValue = false
}

/// Fans a held tab's bubbles out past the bar, and puts the label past the
/// bubble it names; see `TabQuickSwitchPlacement`. Fills the overlay, whose
/// space the frames are in.
struct TabQuickSwitchFanLayout: Layout {
    var tab: CGRect
    var bar: CGRect
    var area: CGRect
    var axis: Axis
    var isRightToLeft: Bool
    /// The bubble the label names. Nil only while there is no label.
    var labelIndex: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let bubbles = subviews.filter { !$0[TabQuickSwitchFanLabel.self] }
        let sizes = bubbles.map { $0.sizeThatFits(.unspecified) }
        let diameter = sizes.map { max($0.width, $0.height) }.max() ?? 0
        // The overlay shows the list where no fan fits; until it swaps, the
        // bubbles wait at the held tab.
        let fan = TabQuickSwitchPlacement.fan(
            count: bubbles.count, diameter: diameter, tab: tab, bar: bar, area: area, axis: axis,
            isRightToLeft: isRightToLeft, spacing: TabQuickSwitchMetrics.spacing
        ) ?? TabQuickSwitchFan(centers: Array(repeating: CGPoint(x: tab.midX, y: tab.midY), count: bubbles.count),
                               pivot: CGPoint(x: tab.midX, y: tab.midY))
        for (bubble, center) in zip(bubbles, fan.centers) {
            bubble.place(at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y), anchor: .center,
                         proposal: .unspecified)
        }
        guard let label = subviews.first(where: { $0[TabQuickSwitchFanLabel.self] }),
              let labelIndex, fan.centers.indices.contains(labelIndex) else { return }
        let size = label.sizeThatFits(.unspecified)
        let center = TabQuickSwitchPlacement.fanLabelCenter(
            size: size, bubble: fan.centers[labelIndex], diameter: diameter, pivot: fan.pivot, area: area,
            spacing: TabQuickSwitchMetrics.spacing
        )
        label.place(at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y), anchor: .center,
                    proposal: ProposedViewSize(size))
    }
}
