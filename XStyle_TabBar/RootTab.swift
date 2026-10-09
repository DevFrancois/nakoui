import SwiftUI

/// The bottom tab bar's sections. Home holds the top menu and its pages.
enum RootTab: Hashable, CaseIterable {
    case home
    case notifications
    case profile
    case search

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .notifications: "Notifications"
        case .profile: "Profile"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .notifications: "bell"
        case .profile: "person"
        case .search: "magnifyingglass"
        }
    }

    /// What a tab will offer, shown until it's built.
    var placeholderDescription: LocalizedStringResource {
        switch self {
        case .home: "Your feed."
        case .notifications: "Likes, replies and quiz results will show up here."
        case .profile: "Your pets, bookmarks and best scores will live here."
        case .search: "Search breeds, articles and quizzes."
        }
    }

    /// Tabs that only show a placeholder for now, in tab bar order. Search is
    /// left out: its role places it apart, at the end of the bar.
    static let placeholderTabs: [RootTab] = [.notifications, .profile]
}
