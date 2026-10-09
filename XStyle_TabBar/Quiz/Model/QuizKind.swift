import SwiftUI

/// The quiz formats offered by the Quizz tab. Also the navigation value and
/// zoom transition ID that open each one.
enum QuizKind: String, CaseIterable, Identifiable, Hashable {
    case classic
    case dogOrCat
    case lightning
    case estimate

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .classic: "Pet Trivia"
        case .dogOrCat: "Dog or Cat?"
        case .lightning: "Lightning Round"
        case .estimate: "Best Guess"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .classic: "Four choices, one right answer."
        case .dogOrCat: "Swipe each fact to the right animal."
        case .lightning: "True or false, before time runs out."
        case .estimate: "Slide to your closest guess."
        }
    }

    var symbol: String {
        switch self {
        case .classic: "checklist"
        case .dogOrCat: "pawprint.fill"
        case .lightning: "bolt.fill"
        case .estimate: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .classic: .teal
        case .dogOrCat: .orange
        case .lightning: .pink
        case .estimate: .green
        }
    }

    /// The ambient light behind the quiz screen.
    var palette: AmbientGradientPalette {
        switch self {
        case .classic: .lagoonMist
        case .dogOrCat: .peachBloom
        case .lightning: .roseDawn
        case .estimate: .meadowLight
        }
    }

    var questionCount: Int {
        switch self {
        case .classic: QuizBank.choiceQuestions.count
        case .dogOrCat: QuizBank.speciesStatements.count
        case .lightning: QuizBank.trueFalseStatements.count
        case .estimate: QuizBank.estimateQuestions.count
        }
    }

    /// Where the best score is kept between launches.
    var bestScoreKey: String {
        "quiz.best.\(rawValue)"
    }
}
