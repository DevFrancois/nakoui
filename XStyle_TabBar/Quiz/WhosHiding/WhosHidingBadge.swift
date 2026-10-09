import SwiftUI

/// A glass capsule on the pane: who was hiding once the round is answered,
/// or a nudge to answer once the glass has fully cleared. The pane's window
/// glass morphs into it.
struct WhosHidingBadge: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color?

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(tint?.opacity(0.3)), in: .capsule)
    }
}

#Preview {
    VStack {
        WhosHidingBadge(title: "Who's that?", systemImage: "questionmark", tint: nil)
        WhosHidingBadge(title: "It's a rabbit!", systemImage: "sparkles", tint: .pink)
    }
    .padding()
    .background(.purple.gradient)
}
