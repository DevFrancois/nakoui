import SwiftUI

struct Article: Identifiable, Hashable {
    /// Also used as the zoom transition ID, so the feed row and the article view stay in sync.
    let id: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    /// Placeholder copy, intentionally not localized.
    let body: String
    let tint: Color
    /// The cover: shown in the feed and first in the article.
    let image: ImageResource
    /// Shown after the cover in the article's gallery.
    let additionalImages: [ImageResource]

    /// Every image, cover first.
    var images: [ImageResource] {
        [image] + additionalImages
    }

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
    static func placeholder(number: Int, tint: Color) -> Article {
        // Every third article, from the second, holds a gallery of the next images in turn.
        let imageCount = number % 3 == 2 ? 3 : 1
        let images = (0..<imageCount).map { offset in
            sampleImages[(number - 1 + offset) % sampleImages.count]
        }

        return Article(
            id: "article-\(number)",
            title: "Lorem Ipsum Dolor Sit Amet \(number)",
            summary: "Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.",
            body: loremIpsum,
            tint: tint,
            image: images[0],
            additionalImages: Array(images.dropFirst())
        )
    }

    /// The images in the asset catalog, shared out across the feed in turn.
    private static let sampleImages: [ImageResource] = [
        .pic1, .pic2, .pic3, .pic4, .pic5, .pic6, .pic7
    ]

    private static let loremIpsum = """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

    Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

    Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.

    Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit.

    Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur. Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur.

    At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident.
    """
}
