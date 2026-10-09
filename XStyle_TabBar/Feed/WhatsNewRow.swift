import SwiftUI

/// The bookmarks feed's first row: a tinted glass card that opens the What's
/// New sheet. The glass stays still when pressed; the whole card is the tap
/// target.
struct WhatsNewRow: View {
    let tint: Color
    let action: () -> Void

    private static let cornerRadius: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Text("What's New")
                .font(.title.bold())
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        // The colour is a fill, not a glass tint: the snapshot iOS takes for
        // the app switcher drops glass rendering, tint included.
        .background(tint.opacity(0.2), in: .rect(cornerRadius: Self.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .accessibilityIdentifier("bookmarks.whatsNew")
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    WhatsNewRow(tint: .blue) {}
}
