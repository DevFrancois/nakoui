import SwiftUI

/// A chip tap's jump from one page to another, possibly distant, page.
struct TabTransition {
    let source: AppTab
    let destination: AppTab

    var offsetFactor: CGFloat {
        let sourceIndex = AppTab.allCases.firstIndex(of: source) ?? 0
        let destinationIndex = AppTab.allCases.firstIndex(of: destination) ?? 0
        let distance = max(abs(destinationIndex - sourceIndex), 1)
        return 1 / CGFloat(distance) - 1
    }
}
