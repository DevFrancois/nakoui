//
//  SheetDetent.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Resting positions of the custom sheet, from lowest to highest. `allCases` keeps this order.
nonisolated enum SheetDetent: String, CaseIterable, Sendable {
    /// Below the screen: no result to show, as while the scanner aims. A release moving down from medium lands here.
    case hidden
    /// The old `.height(350)` detent.
    case medium
    /// The old `.large` detent; the only one where the content scrolls.
    case full
}

extension SheetDetent: Comparable {
    /// Lower detents first, in `allCases` order.
    static func < (lhs: SheetDetent, rhs: SheetDetent) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One value per detent: the sheet tops, or a metric interpolated between detents.
nonisolated struct DetentValues: Equatable, Sendable {
    var hidden: CGFloat
    var medium: CGFloat
    var full: CGFloat

    static func constant(_ value: CGFloat) -> DetentValues {
        DetentValues(hidden: value, medium: value, full: value)
    }

    subscript(detent: SheetDetent) -> CGFloat {
        switch detent {
        case .hidden:
            hidden
        case .medium:
            medium
        case .full:
            full
        }
    }

    /// Linear between the medium and full `tops`, clamped past them: below medium the sheet only slides away.
    func value(at top: CGFloat, tops: DetentValues) -> CGFloat {
        if top >= tops.medium {
            return medium
        }
        if top >= tops.full, tops.medium > tops.full {
            let t = (top - tops.full) / (tops.medium - tops.full)
            return full + (medium - full) * t
        }
        return full
    }
}
