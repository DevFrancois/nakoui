import SwiftUI

/// Stand-in content for a bottom tab that isn't built yet.
struct RootTabPlaceholder: View {
    let title: LocalizedStringResource
    let systemImage: String
    let description: LocalizedStringResource

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
    }
}

#Preview {
    RootTabPlaceholder(title: "Profile", systemImage: "person", description: "Your profile will live here.")
}
