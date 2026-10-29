import SwiftUI

enum TabQuickSwitchMetrics {
    /// Between the bar and its menu, between bubbles, and around a label.
    static let spacing: CGFloat = 10
    /// Keeps a menu off the screen's edges.
    static let margin: CGFloat = 16
    static let listInset: CGFloat = 6
    static let listCornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 18
    static let rowSymbolWidth: CGFloat = 28
    /// How near a too-tall list's edge the finger scrolls it, and how fast
    /// at the very edge, in points a second.
    static let listScrollBand: CGFloat = 36
    static let listScrollSpeed: CGFloat = 240
    static let bubbleDiameter: CGFloat = 56
    /// How far the spotlight's edge fades.
    static let spotlightFeather: CGFloat = 48
    /// The fan's angle between neighbouring bubbles, and the most it sweeps.
    static let fanStep: CGFloat = .pi * 34 / 180
    static let fanMaximumSpan: CGFloat = .pi * 110 / 180
    /// The lowest a bubble may sit, as an angle off the bar's edge.
    static let fanMinimumElevation: CGFloat = .pi * 15 / 180
    /// How far the fan may tilt off straight out to stay on screen, and the
    /// steps it tries.
    static let fanMaximumTilt: CGFloat = .pi * 30 / 180
    static let fanTiltStep: CGFloat = .pi / 180
}

/// Bubbles fanned out around a held tab; see `TabQuickSwitchPlacement.fan`.
struct TabQuickSwitchFan: Equatable {
    var centers: [CGPoint]
    /// What the arc turns about: the held tab's centre, moved with the fan
    /// when it had to move to stay on screen.
    var pivot: CGPoint
}

/// Where a held tab's menu goes, in the overlay's space. `area` is the safe
/// part of the screen a menu may use, which the bar is outside of.
enum TabQuickSwitchPlacement {
    /// A list card of `size`: just past the bar's outer edge, centred on the
    /// held tab, inside `area`. Too tall for the room, it takes all there is
    /// and scrolls; see `TabQuickSwitchListScroll`.
    static func listFrame(size: CGSize, tab: CGRect, bar: CGRect, area: CGRect, axis: Axis,
                          spacing: CGFloat) -> CGRect {
        let width = min(size.width, area.width)
        switch axis {
        case .horizontal:
            let height = min(size.height, max(0, bar.minY - spacing - area.minY))
            return CGRect(x: clamp(tab.midX - width / 2, area.minX, area.maxX - width),
                          y: bar.minY - spacing - height, width: width, height: height)
        case .vertical:
            let height = min(size.height, area.height)
            let x = isLeadingRail(bar, in: area) ? bar.maxX + spacing : bar.minX - spacing - width
            return CGRect(x: x, y: clamp(tab.midY - height / 2, area.minY, area.maxY - height),
                          width: width, height: height)
        }
    }

    /// The centres of `count` bubbles of `diameter`, fanned out from the held
    /// tab past the bar's outer edge, the first item leading (or on top).
    /// The fan tilts, then moves, as little as keeps it inside `area`, which
    /// for this reaches as far as the bar. Nil when no fan fits, for the
    /// list to show instead.
    static func fan(count: Int, diameter: CGFloat, tab: CGRect, bar: CGRect, area: CGRect, axis: Axis,
                    isRightToLeft: Bool, spacing: CGFloat) -> TabQuickSwitchFan? {
        let pivot = CGPoint(x: tab.midX, y: tab.midY)
        // Outward leaves the bar; along runs from the first item to the last.
        let outward: CGVector
        let along: CGVector
        // From the pivot to the bar's outer edge.
        let edge: CGFloat
        // The area, reaching the bar on its side: the radius keeps bubbles
        // clear of the bar, so they may sit as close as a list does.
        var allowed = area
        switch axis {
        case .horizontal:
            outward = CGVector(dx: 0, dy: -1)
            along = CGVector(dx: isRightToLeft ? -1 : 1, dy: 0)
            edge = pivot.y - bar.minY
            allowed.size.height = max(area.maxY, bar.minY - spacing) - area.minY
        case .vertical:
            let isLeading = isLeadingRail(bar, in: area)
            outward = CGVector(dx: isLeading ? 1 : -1, dy: 0)
            along = CGVector(dx: 0, dy: 1)
            edge = isLeading ? bar.maxX - pivot.x : pivot.x - bar.minX
            if isLeading {
                allowed.origin.x = min(area.minX, bar.maxX + spacing)
                allowed.size.width = area.maxX - allowed.minX
            } else {
                allowed.size.width = max(area.maxX, bar.minX - spacing) - area.minX
            }
        }
        let step = count > 1 ? min(TabQuickSwitchMetrics.fanStep, TabQuickSwitchMetrics.fanMaximumSpan / CGFloat(count - 1)) : 0
        // Neighbouring centres stay a bubble and a gap apart.
        let chordRadius = count > 1 ? (diameter + spacing) / (2 * sin(step / 2)) : 0
        let inner = allowed.insetBy(dx: diameter / 2, dy: diameter / 2)

        func centers(tilt: CGFloat) -> [CGPoint]? {
            // Angles turn from `along` towards `outward`: a quarter turn
            // points straight out, and the first item turns the furthest.
            let angles = (0..<count).map { .pi / 2 + tilt + (CGFloat(count - 1) / 2 - CGFloat($0)) * step }
            guard let lowest = angles.map(sin).min(), lowest >= sin(TabQuickSwitchMetrics.fanMinimumElevation) else {
                return nil
            }
            // Every bubble clears the bar's edge by a gap.
            let radius = max(chordRadius, (edge + spacing + diameter / 2) / lowest)
            return angles.map { angle in
                CGPoint(x: pivot.x + radius * (cos(angle) * along.dx + sin(angle) * outward.dx),
                        y: pivot.y + radius * (cos(angle) * along.dy + sin(angle) * outward.dy))
            }
        }

        var best: (centers: [CGPoint], move: CGVector)?
        let tilts = stride(from: 0, through: TabQuickSwitchMetrics.fanMaximumTilt, by: TabQuickSwitchMetrics.fanTiltStep)
            .flatMap { $0 == 0 ? [$0] : [$0, -$0] }
        for tilt in tilts {
            // A fan too big to fit whole would be squeezed: tilting further
            // out lowers the end bubbles, and the radius grows to clear the bar.
            guard let candidate = centers(tilt: tilt), fits(candidate, in: inner) else { continue }
            let move = shift(bringing: candidate, into: inner)
            if move == .zero { return TabQuickSwitchFan(centers: candidate, pivot: pivot) }
            if best.map({ hypot(move.dx, move.dy) < hypot($0.move.dx, $0.move.dy) }) ?? true {
                best = (candidate, move)
            }
        }
        guard let chosen = best else { return nil }
        // Clamped too, so rounding in the move never leaves a bubble a
        // fraction outside.
        let placed = chosen.centers.map {
            CGPoint(x: clamp($0.x + chosen.move.dx, inner.minX, inner.maxX),
                    y: clamp($0.y + chosen.move.dy, inner.minY, inner.maxY))
        }
        return TabQuickSwitchFan(centers: placed,
                                 pivot: CGPoint(x: pivot.x + chosen.move.dx, y: pivot.y + chosen.move.dy))
    }

    /// The centre of a label of `size` for the bubble at `bubble`: past it,
    /// away from the fan's pivot, where no other bubble is, inside `area`.
    static func fanLabelCenter(size: CGSize, bubble: CGPoint, diameter: CGFloat, pivot: CGPoint, area: CGRect,
                               spacing: CGFloat) -> CGPoint {
        let dx = bubble.x - pivot.x
        let dy = bubble.y - pivot.y
        let length = hypot(dx, dy)
        guard length > 0 else { return bubble }
        let direction = CGVector(dx: dx / length, dy: dy / length)
        // The label's half-extent along that direction keeps its edge a gap
        // from the bubble's.
        let reach = diameter / 2 + spacing + (abs(direction.dx) * size.width + abs(direction.dy) * size.height) / 2
        return CGPoint(x: clamp(bubble.x + direction.dx * reach, area.minX + size.width / 2, area.maxX - size.width / 2),
                       y: clamp(bubble.y + direction.dy * reach, area.minY + size.height / 2, area.maxY - size.height / 2))
    }

    /// Whether a vertical bar sits on the screen's leading side, so its menu
    /// opens towards the trailing one.
    private static func isLeadingRail(_ bar: CGRect, in area: CGRect) -> Bool {
        bar.midX < area.midX
    }

    /// Whether some move brings every point inside `area`.
    private static func fits(_ points: [CGPoint], in area: CGRect) -> Bool {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return true }
        return maxX - minX <= area.width && maxY - minY <= area.height
    }

    /// The least move that brings every point inside `area`. Too wide for
    /// it, the points line up with its leading or top edge.
    private static func shift(bringing points: [CGPoint], into area: CGRect) -> CGVector {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return .zero }
        func offset(_ low: CGFloat, _ high: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            if low < lower { return lower - low }
            if high > upper { return max(upper - high, lower - low) }
            return 0
        }
        return CGVector(dx: offset(minX, maxX, area.minX, area.maxX), dy: offset(minY, maxY, area.minY, area.maxY))
    }

    /// `value` within `lower...upper`; `lower` when they cross.
    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
