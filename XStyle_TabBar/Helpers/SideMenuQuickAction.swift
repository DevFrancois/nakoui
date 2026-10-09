import SwiftUI

/// The side menu's two quick actions, under the profile.
nonisolated enum SideMenuQuickAction: CaseIterable, Identifiable {
    case bookmarks
    case likes

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .bookmarks: "Bookmarks"
        case .likes: "Likes"
        }
    }

    var symbol: String {
        switch self {
        case .bookmarks: "bookmark.fill"
        case .likes: "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bookmarks: .blue
        case .likes: .pink
        }
    }

    /// Placeholder counts, until real data exists.
    var count: Int {
        switch self {
        case .bookmarks: 128
        case .likes: 2_400
        }
    }
}
