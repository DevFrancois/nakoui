#if DEBUG
import SwiftUI

/// Home background comparisons stay reachable while the side menu is off.
struct ProfileDebugSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeBackgroundStyle.storageKey) private var backgroundStyle = HomeBackgroundStyle.pageAttached

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Original blended background", isOn: usesOriginalBackground)
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

    private var usesOriginalBackground: Binding<Bool> {
        Binding {
            backgroundStyle == .originalBlended
        } set: { usesOriginal in
            backgroundStyle = usesOriginal ? .originalBlended : .pageAttached
        }
    }
}

#Preview {
    ProfileDebugSettings()
}
#endif
