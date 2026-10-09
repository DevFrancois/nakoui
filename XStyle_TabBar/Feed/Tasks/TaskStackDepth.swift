import SwiftUI

/// A card's place in the task stack; 0 is the front. Read by
/// `TaskStackLayout`, so a card on its way out doesn't hold the others back
/// while it leaves.
nonisolated struct TaskStackDepth: LayoutValueKey {
    static let defaultValue = 0
}
