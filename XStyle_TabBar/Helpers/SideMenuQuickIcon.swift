import SwiftUI

/// A quick action's symbol, or a spinner while it loads.
struct SideMenuQuickIcon: View {
    let action: SideMenuQuickAction
    let isLoading: Bool

    var body: some View {
        ZStack {
            Image(systemName: action.symbol)
                .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityHidden(true)
    }
}
