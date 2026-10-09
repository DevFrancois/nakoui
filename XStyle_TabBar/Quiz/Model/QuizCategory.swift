import Foundation

/// How the Quizz tab groups its games.
enum QuizCategory: CaseIterable, Identifiable {
    case justForFun
    case classics
    case brainTeasers
    case arcade

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .justForFun: "Just for Fun"
        case .classics: "Classics"
        case .brainTeasers: "Brain Teasers"
        case .arcade: "Arcade"
        }
    }

    var symbol: String {
        switch self {
        case .justForFun: "sparkles"
        case .classics: "book.closed.fill"
        case .brainTeasers: "brain.head.profile.fill"
        case .arcade: "gamecontroller.fill"
        }
    }

    var kinds: [QuizKind] {
        QuizKind.allCases.filter { $0.category == self }
    }
}
