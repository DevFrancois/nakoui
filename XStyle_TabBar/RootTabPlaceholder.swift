import SwiftUI

/// Stand-in content for a bottom tab that isn't built yet.
struct RootTabPlaceholder: View {
    let tab: RootTab

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.symbol)
            }
        } description: {
            Text(tab.placeholderDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
    }
}

#Preview {
    RootTabPlaceholder(tab: .search)
}
