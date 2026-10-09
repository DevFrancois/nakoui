import SwiftUI

/// Tells `WordWagBoardLayout` where to place a subview.
nonisolated struct WordWagSpotKey: LayoutValueKey {
    static let defaultValue = WordWagSpot.guess
}
