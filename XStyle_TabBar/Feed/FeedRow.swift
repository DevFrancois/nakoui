import SwiftUI

/// A placeholder post: an avatar, a title and a few lines of grey text.
struct FeedRow: View {
    let tab: AppTab
    let number: Int
    var settledWidth: CGFloat? = nil

    private static let avatarWidth: CGFloat = 44
    private static let avatarSpacing: CGFloat = 8

    var body: some View {
        let textWidth = settledWidth.map {
            max(0, $0 - 2 * FeedLayoutMetrics.horizontalPadding - Self.avatarWidth - Self.avatarSpacing)
        }

        HStack(alignment: .top, spacing: Self.avatarSpacing) {
            Circle()
                .fill(tab.tint.tertiary)
                .frame(width: Self.avatarWidth, height: Self.avatarWidth)

            VStack(alignment: .leading, spacing: 8) {
                SettledWidthLayout(width: textWidth) {
                    Text("\(tab.title) post \(number)")
                        .font(.headline)
                }

                ForEach(lineWidths.indices, id: \.self) { line in
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.quaternary)
                            .frame(width: geometry.size.width * lineWidths[line])
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(FeedLayoutMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.title) post \(number)")
    }

    /// Fractions of the row width, varied per post so the feed doesn't look tiled.
    private var lineWidths: [CGFloat] {
        let lastLine: [CGFloat] = [0.35, 0.5, 0.42]
        return number.isMultiple(of: 2)
            ? [0.7, lastLine[number % 3]]
            : [0.7, 0.66, lastLine[number % 3]]
    }
}
