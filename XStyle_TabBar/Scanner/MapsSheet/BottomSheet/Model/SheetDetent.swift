//
//  SheetDetent.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Resting positions of the custom sheet, from lowest to highest. `allCases` keeps this order.
nonisolated enum SheetDetent: String, CaseIterable, Sendable {
    /// The old `.height(80)` detent.
    case collapsed
    /// The old `.height(350)` detent.
    case medium
    /// The old `.large` detent; the only one where the content scrolls.
    case full
}

/// One value per detent: the sheet tops, or a metric interpolated between detents.
nonisolated struct DetentValues: Equatable, Sendable {
    var collapsed: CGFloat
    var medium: CGFloat
    var full: CGFloat

    static func constant(_ value: CGFloat) -> DetentValues {
        DetentValues(collapsed: value, medium: value, full: value)
    }

    subscript(detent: SheetDetent) -> CGFloat {
        switch detent {
        case .collapsed:
            collapsed
        case .medium:
            medium
        case .full:
            full
        }
    }

    /// Linear between the detents' sheet `tops`, clamped past the ends.
    func value(at top: CGFloat, tops: DetentValues) -> CGFloat {
        if top >= tops.collapsed {
            return collapsed
        }
        if top >= tops.medium, tops.collapsed > tops.medium {
            let t = (top - tops.medium) / (tops.collapsed - tops.medium)
            return medium + (collapsed - medium) * t
        }
        if top >= tops.full, tops.medium > tops.full {
            let t = (top - tops.full) / (tops.medium - tops.full)
            return full + (medium - full) * t
        }
        return full
    }
}
