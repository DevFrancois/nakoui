import SwiftUI

/// A page the top menu offers as a chip.
protocol TopMenuTab: CaseIterable, Hashable {
    var title: String { get }
    /// An outline SF Symbol name; chips draw its filled variant.
    var symbol: String { get }
    var tint: Color { get }
}
