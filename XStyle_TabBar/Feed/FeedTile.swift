import SwiftUI

/// A tinted glass tile with a caption and a title in its bottom corner. The
/// For you feed adapts its columns under the What's New card. Like that card,
/// the glass stays still when pressed; the whole tile is the tap target.
struct FeedTile: View {
    let caption: LocalizedStringResource
    let title: LocalizedStringResource
    let tint: Color
    var size: FeedTileSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettledWidth {
                ZStack(alignment: .bottomLeading) {
                    // The artwork supplies the preferred proportions; text can
                    // still make the card taller when it needs more room. At
                    // rest width, so the surface can widen without moving its
                    // bottom label.
                    Color.clear
                        .aspectRatio(size.aspectRatio, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(caption)
                            .font(size.captionFont)
                            .foregroundStyle(.secondary)

                        Text(title)
                            .font(size.titleFont)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(size.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(.rect(cornerRadius: size.cornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .modifier(FeedGlass(cornerRadius: size.cornerRadius, tint: tint, tintOpacity: 0.25))
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
