import SwiftUI

/// The home screen's pages, in pager order.
enum AppTab: String, TopMenuTab {
    case bookmarks = "Bookmarks"
    case videos = "Videos"
    case articles = "Articles"
    case likes = "Likes"
    case quizz = "Quizz"

    var title: String {
        switch self {
        case .bookmarks: "For you"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .bookmarks: "bookmark"
        case .videos: "play.square.stack"
        case .articles: "long.text.page.and.pencil"
        case .likes: "heart"
        case .quizz: "pawprint"
        }
    }

    var tint: Color {
        switch self {
        case .bookmarks: .blue
        case .videos: .orange
        case .articles: .green
        case .likes: .pink
        case .quizz: .teal
        }
    }

    var palette: AmbientGradientPalette {
        switch self {
        case .bookmarks: .lavenderHealth
        case .videos: .peachBloom
        case .articles: .meadowLight
        case .likes: .roseDawn
        case .quizz: .lagoonMist
        }
    }

    /// Position in the pager.
    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
