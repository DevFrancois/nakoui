import SwiftUI

/// Stand-in content for a bottom tab that isn't built yet.
struct RootTabPlaceholder: View {
    let tab: RootTab

    #if DEBUG
    @State private var isShowingDebugSettings = false
    #endif

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.symbol)
            }
        } description: {
            Text(tab.placeholderDescription)
        } actions: {
            #if DEBUG
            if tab == .profile {
                Button("Debug Settings", systemImage: "slider.horizontal.3") {
                    isShowingDebugSettings = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("profile.debugSettings")
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugSettings) {
            ProfileDebugSettings()
        }
        #endif
    }
}

#Preview {
    RootTabPlaceholder(tab: .profile)
}
