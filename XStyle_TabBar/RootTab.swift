import SwiftUI

/// The bottom tab bar's sections. Home holds the top menu and its pages.
enum RootTab: Hashable, CaseIterable {
    case home
    case scanner
    case profile
    case search

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .scanner: "Scan"
        case .profile: "Profile"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .scanner: "barcode.viewfinder"
        case .profile: "person"
        case .search: "magnifyingglass"
        }
    }

    /// What a tab will offer, shown until it's built.
    var placeholderDescription: LocalizedStringResource {
        switch self {
        case .home: "Your feed."
        case .scanner: "Scan product barcodes."
        case .profile: "Your pets, bookmarks and best scores will live here."
        case .search: "Search breeds, articles and quizzes."
        }
    }

    /// Tabs that only show a placeholder for now. Search is declared separately.
    static let placeholderTabs: [RootTab] = [.profile]
}
