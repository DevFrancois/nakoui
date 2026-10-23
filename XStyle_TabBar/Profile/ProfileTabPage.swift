import SwiftUI

/// The Profile tab, still a stand-in. Debug builds put the tab bar's motion
/// dials here instead, right above the bar they tune.
struct ProfileTabPage: View {
    #if DEBUG
    @State private var isShowingDebugSettings = false
    #endif

    var body: some View {
        #if DEBUG
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label {
                        Text(RootTab.profile.title)
                    } icon: {
                        Image(systemName: RootTab.profile.symbol)
                    }
                    .font(.title2.bold())

                    Spacer(minLength: 8)

                    Button("Debug Settings", systemImage: "slider.horizontal.3") {
                        isShowingDebugSettings = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("profile.debugSettings")
                }

                GlassTabBarDebugControls()
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 24))
            }
            .padding()
        }
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
        .sheet(isPresented: $isShowingDebugSettings) {
            ProfileDebugSettings()
        }
        #else
        RootTabPlaceholder(tab: .profile)
        #endif
    }
}

#Preview {
    ProfileTabPage()
}
