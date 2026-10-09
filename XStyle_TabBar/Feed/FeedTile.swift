import SwiftUI

/// A tinted glass tile with a caption and a title in its bottom corner. The
/// For you feed shows rows of two under the What's New card. Like that card,
/// the glass stays still when pressed; the whole tile is the tap target.
struct FeedTile: View {
    let caption: String
    let title: String
    let tint: Color
    var size: FeedTileSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(size.captionFont)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(size.titleFont)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(size.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .aspectRatio(size.aspectRatio, contentMode: .fit)
            .contentShape(.rect(cornerRadius: size.cornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        // The colour is a fill, not a glass tint: the snapshot iOS takes for
        // the app switcher drops glass rendering, tint included.
        .background(tint.opacity(0.25), in: .rect(cornerRadius: size.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: size.cornerRadius))
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            FeedTile(caption: "Placeholder caption", title: "First", tint: .purple) {}
            FeedTile(caption: "Placeholder caption", title: "Second", tint: .teal) {}
        }

        HStack(spacing: 12) {
            FeedTile(caption: "Placeholder caption", title: "Third", tint: .purple, size: .compact) {}
            FeedTile(caption: "Placeholder caption", title: "Fourth", tint: .teal, size: .compact) {}
        }
    }
    .padding()
}
