import SwiftUI

/// The bookmarks feed's first row: a tinted glass card that opens the What's
/// New sheet. The glass stays still when pressed; the whole card is the tap
/// target.
struct WhatsNewRow: View {
    let tint: Color
    var settledWidth: CGFloat? = nil
    let action: () -> Void

    private static let cornerRadius: CGFloat = 32

    var body: some View {
        Button(action: action) {
            SettledWidthLayout(width: settledWidth.map { $0 - 2 * FeedLayoutMetrics.horizontalPadding }) {
                Text("What's New")
                    .font(.title.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .modifier(FeedGlass(cornerRadius: Self.cornerRadius, tint: tint, tintOpacity: 0.2))
        .accessibilityIdentifier("bookmarks.whatsNew")
        .padding(.horizontal, FeedLayoutMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }
}

#Preview {
    WhatsNewRow(tint: .blue) {}
}
