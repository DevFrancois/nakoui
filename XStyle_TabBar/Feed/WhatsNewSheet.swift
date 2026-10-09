import SwiftUI

/// A modal listing recent changes to the app.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Label("Swipe between tabs, or tap a chip to jump straight to one.", systemImage: "rectangle.stack")
                Label("Drag from the left edge to open the side menu.", systemImage: "sidebar.left")
                Label("The top menu tucks away as you scroll down.", systemImage: "arrow.up.and.down")
            }
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

#Preview {
    WhatsNewSheet()
}
