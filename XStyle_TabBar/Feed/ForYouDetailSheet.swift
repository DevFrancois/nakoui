import SwiftUI

/// A modal of placeholder lines for one of the For you feed's cards.
struct ForYouDetailSheet: View {
    let destination: ForYouDestination

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(destination.items, id: \.self) { item in
                Label(item.text, systemImage: item.symbol)
            }
            .tint(destination.tint)
            .navigationTitle(destination.title)
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
    ForYouDetailSheet(destination: .whatsNew)
}
