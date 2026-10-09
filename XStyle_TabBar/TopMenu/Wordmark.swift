import SwiftUI

/// The menu's title, set like ZoomInUIKit's serif wordmark.
struct Wordmark: View {
    let title: String

    var body: some View {
        Text(kernedTitle)
            .font(TopMenuMetrics.wordmarkFont)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    /// Tightens only the gaps between letters, so the last glyph keeps its
    /// width and the centred word doesn't shift.
    private var kernedTitle: AttributedString {
        var text = AttributedString(title)
        if let last = text.characters.indices.last {
            text[text.startIndex..<last].kern = TopMenuMetrics.wordmarkKerning
        }
        return text
    }
}
