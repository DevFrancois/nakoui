import SwiftUI

/// Hands each bubble's drift to `BubblePopLayout`.
nonisolated struct BubblePopDriftKey: LayoutValueKey {
    static let defaultValue = BubblePopDrift.still
}
