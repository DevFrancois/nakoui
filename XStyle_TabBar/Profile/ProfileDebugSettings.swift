#if DEBUG
import SwiftUI

/// Home background comparisons stay reachable while the side menu is off.
struct ProfileDebugSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeBackgroundStyle.storageKey) private var backgroundStyle = HomeBackgroundStyle.defaultStyle

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Original blended background", isOn: $backgroundStyle.usesOriginalBlended)
                        .accessibilityIdentifier("debug.originalBlendedBackground")
                } header: {
                    Text("Home background")
                } footer: {
                    Text("When off, each page carries its own color as it moves.")
                }

                Section {
                    GradientDebugControls()
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }

}

#Preview {
    ProfileDebugSettings()
}
#endif
