import SwiftUI

/// Marks a feed thumbnail whose article holds more than one image.
struct ArticleImageCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count)", systemImage: "square.on.square")
            .font(.footnote)
            .bold()
            .padding(.horizontal, ArticleMetrics.galleryIndicatorPadding * 1.5)
            .padding(.vertical, ArticleMetrics.galleryIndicatorPadding)
            .glassEffect(in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("^[\(count) image](inflect: true)"))
    }
}

#Preview {
    ArticleImageCountBadge(count: 3)
        .padding()
        .background(.green)
}
