import Foundation

/// What a search looks through.
enum SearchScope: String, CaseIterable, Identifiable {
    case breeds
    case articles
    case quizzes

    /// The scope last chosen, kept across launches.
    static let storageKey = "search.scope"
    static let defaultScope = Self.breeds

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .breeds: "Breeds"
        case .articles: "Articles"
        case .quizzes: "Quizzes"
        }
    }

    var symbol: String {
        switch self {
        case .breeds: "pawprint"
        case .articles: "doc.text.magnifyingglass"
        case .quizzes: "questionmark.circle"
        }
    }

    /// What searching this scope will find, shown until search is built.
    var placeholderDescription: LocalizedStringResource {
        switch self {
        case .breeds: "Find a breed's temperament, care and health."
        case .articles: "Find articles on food, health and training."
        case .quizzes: "Find quizzes to test what you know."
        }
    }
}
