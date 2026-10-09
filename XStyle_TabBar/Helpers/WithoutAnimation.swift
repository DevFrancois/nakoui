import SwiftUI

/// Applies `action` with every animation disabled, including ones that
/// views declare themselves.
func withoutAnimation(_ action: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, action)
}
