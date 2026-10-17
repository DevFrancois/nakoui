import SwiftUI

/// A placeholder post: an avatar, a title and a few lines of grey text.
struct FeedRow: View {
    let tab: AppTab
    let number: Int

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(tab.tint.tertiary)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(tab.title) post \(number)")
                    .font(.headline)

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
        .padding()
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
