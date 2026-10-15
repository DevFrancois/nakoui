import SwiftUI

/// What kind of thing a history entry was.
enum HistoryKind: CaseIterable, Identifiable {
    case article
    case video
    case quiz
    case post

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .article: "Articles"
        case .video: "Videos"
        case .quiz: "Quizzes"
        case .post: "Posts"
        }
    }

    var symbol: String {
        switch self {
        case .article: "doc.text.fill"
        case .video: "play.rectangle.fill"
        case .quiz: "pawprint.fill"
        case .post: "text.bubble.fill"
        }
    }

    var tint: Color {
        switch self {
        case .article: .green
        case .video: .orange
        case .quiz: .teal
        case .post: .blue
        }
    }
}
