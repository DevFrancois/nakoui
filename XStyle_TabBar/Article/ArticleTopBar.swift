import SwiftUI

/// Back and Share, drawn by the article itself rather than the navigation bar,
/// so they shrink away with the page when the zoom is dragged closed.
struct ArticleTopBar: View {
    let article: Article

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button("Back", systemImage: "chevron.backward", action: goBack)

            Spacer()

            ShareLink(
                item: String(localized: article.title),
                subject: Text(article.title),
                message: Text(article.summary)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .buttonStyle(GlassCircleButtonStyle())
        .padding(.horizontal)
    }

    private func goBack() {
        dismiss()
    }
}
