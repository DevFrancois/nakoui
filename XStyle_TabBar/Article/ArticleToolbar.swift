import SwiftUI

/// Article actions use the system toolbar; NavigationStack supplies Back.
struct ArticleToolbar: ToolbarContent {
    let article: Article

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ShareLink(
                item: String(localized: article.title),
                subject: Text(article.title),
                message: Text(article.summary)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
