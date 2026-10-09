import SwiftUI

/// How large a `FeedTile` draws: a square, or a shorter compact card.
enum FeedTileSize {
    case regular
    case compact

    /// Width over height.
    var aspectRatio: CGFloat {
        switch self {
        case .regular: 1
        case .compact: 1.6
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .regular: 32
        case .compact: 24
        }
    }

    var padding: CGFloat {
        switch self {
        case .regular: 20
        case .compact: 16
        }
    }

    var captionFont: Font {
        switch self {
        case .regular: .subheadline.weight(.medium)
        case .compact: .caption.weight(.medium)
        }
    }

    var titleFont: Font {
        switch self {
        case .regular: .title2.bold()
        case .compact: .headline
        }
    }
}
