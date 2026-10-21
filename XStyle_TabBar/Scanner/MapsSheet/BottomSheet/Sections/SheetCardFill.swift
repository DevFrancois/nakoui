//
//  SheetCardFill.swift
//  MapsIOS26BottomSheet
//

import SwiftUI
import UIKit

/// Card background for the sheet's content: the grouped "secondary" color, which the HIG reserves for grouping content
/// within the overall view. White, or #2C2C2E in dark mode, at the elevated level like the sheet.
///
/// Opaque in every state and independent of what is behind the sheet: the sheet itself carries a frosted grouped
/// backing on its glass (`SheetMetrics.frostedBackingOpacity`) that turns fully opaque at full, so the cards always sit
/// on the same neutral surface, as in Apple Maps at full.
enum SheetCardFill {
    static let color = Color(uiColor: UIColor { traits in
        UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits.modifyingTraits { mutableTraits in
            mutableTraits.userInterfaceLevel = .elevated
        })
    })
}
