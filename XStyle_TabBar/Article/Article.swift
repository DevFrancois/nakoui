import SwiftUI

struct Article: Identifiable, Hashable {
    /// Also used as the zoom transition ID, so the feed row and the article view stay in sync.
    let id: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    /// Placeholder copy, intentionally not localized.
    let body: String
    let tint: Color
    /// Colors of the ambient light behind the article page.
    let palette: AmbientGradientPalette

    // Identity alone decides equality, so navigation compares articles by ID.
    static func == (lhs: Article, rhs: Article) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Article {
    /// A stand-in article for a feed row, until real content exists.
    static func placeholder(number: Int, tint: Color, palette: AmbientGradientPalette) -> Article {
        Article(
            id: "article-\(number)",
            title: "Lorem Ipsum Dolor Sit Amet \(number)",
            summary: "Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.",
            body: loremIpsum,
            tint: tint,
            palette: palette
        )
    }

    private static let loremIpsum = """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

    Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

    Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.

    Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit.

    Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur. Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur.

    At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident.
    """
}
