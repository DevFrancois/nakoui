import SwiftUI

/// The quiz formats offered by the Quizz tab. Also the navigation value and
/// zoom transition ID that open each one.
enum QuizKind: String, CaseIterable, Identifiable, Hashable {
    case classic
    case dogOrCat
    case lightning
    case estimate
    case bubblePop
    case pawPairs
    case mysteryPet
    case wordWag
    case higherLower
    case petMatch
    case lineUp
    case whosHiding

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .classic: "Pet Trivia"
        case .dogOrCat: "Dog or Cat?"
        case .lightning: "Lightning Round"
        case .estimate: "Best Guess"
        case .bubblePop: "Bubble Pop"
        case .pawPairs: "Paw Pairs"
        case .mysteryPet: "Who Am I?"
        case .wordWag: "Word Wag"
        case .higherLower: "Higher or Lower"
        case .petMatch: "Which Dog Are You?"
        case .lineUp: "Line 'Em Up"
        case .whosHiding: "Who's Hiding?"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .classic: "Four choices, one right answer."
        case .dogOrCat: "Swipe each fact to the right animal."
        case .lightning: "True or false, before time runs out."
        case .estimate: "Slide to your closest guess."
        case .bubblePop: "Pop only the right bubbles before time runs out."
        case .pawPairs: "Flip the cards and match the pairs."
        case .mysteryPet: "Name the breed from as few clues as you can."
        case .wordWag: "Unscramble the breed hiding in the letters."
        case .higherLower: "Heavier, faster, longer-lived? Call it."
        case .petMatch: "No wrong answers, just your perfect breed."
        case .lineUp: "Put four pets in the right order."
        case .whosHiding: "Guess the animal before the glass clears."
        }
    }

    var symbol: String {
        switch self {
        case .classic: "checklist"
        case .dogOrCat: "pawprint.fill"
        case .lightning: "bolt.fill"
        case .estimate: "slider.horizontal.3"
        case .bubblePop: "bubbles.and.sparkles.fill"
        case .pawPairs: "square.grid.2x2.fill"
        case .mysteryPet: "magnifyingglass"
        case .wordWag: "textformat.abc"
        case .higherLower: "arrow.up.arrow.down"
        case .petMatch: "heart.text.square.fill"
        case .lineUp: "list.number"
        case .whosHiding: "eye.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .classic: .teal
        case .dogOrCat: .orange
        case .lightning: .pink
        case .estimate: .green
        case .bubblePop: .cyan
        case .pawPairs: .indigo
        case .mysteryPet: .brown
        case .wordWag: .mint
        case .higherLower: .orange
        case .petMatch: .pink
        case .lineUp: .blue
        case .whosHiding: .purple
        }
    }

    /// The ambient light behind the quiz screen.
    var palette: AmbientGradientPalette {
        switch self {
        case .classic: .lagoonMist
        case .dogOrCat: .peachBloom
        case .lightning: .roseDawn
        case .estimate: .meadowLight
        case .bubblePop: .lagoonMist
        case .pawPairs: .lavenderHealth
        case .mysteryPet: .peachBloom
        case .wordWag: .meadowLight
        case .higherLower: .roseDawn
        case .petMatch: .roseDawn
        case .lineUp: .lagoonMist
        case .whosHiding: .lavenderHealth
        }
    }

    var category: QuizCategory {
        switch self {
        case .petMatch: .justForFun
        case .classic, .dogOrCat, .estimate, .mysteryPet: .classics
        case .pawPairs, .wordWag, .lineUp, .whosHiding: .brainTeasers
        case .lightning, .bubblePop, .higherLower: .arcade
        }
    }

    /// Questions, rounds or boards in one game.
    var questionCount: Int {
        switch self {
        case .classic: QuizBank.choiceQuestions.count
        case .dogOrCat: QuizBank.speciesStatements.count
        case .lightning: QuizBank.trueFalseStatements.count
        case .estimate: QuizBank.estimateQuestions.count
        case .bubblePop: BubblePopRounds.count
        case .pawPairs: PawPairsRounds.count
        case .mysteryPet: MysteryPetRounds.count
        case .wordWag: WordWagRounds.count
        case .higherLower: HigherLowerRounds.count
        case .petMatch: PetMatchRounds.count
        case .lineUp: LineUpRounds.count
        case .whosHiding: WhosHidingRounds.count
        }
    }

    /// The most points one game can earn: one per question, unless the
    /// format awards more for answering faster or with fewer hints.
    var maxScore: Int {
        switch self {
        case .classic, .dogOrCat, .lightning, .estimate: questionCount
        case .bubblePop: BubblePopRounds.maxScore
        case .pawPairs: PawPairsRounds.maxScore
        case .mysteryPet: MysteryPetRounds.maxScore
        case .wordWag: WordWagRounds.maxScore
        case .higherLower: HigherLowerRounds.maxScore
        case .petMatch: 0
        case .lineUp: LineUpRounds.maxScore
        case .whosHiding: WhosHidingRounds.maxScore
        }
    }

    /// Whether the game keeps score, and so a best score.
    var isScored: Bool {
        maxScore > 0
    }

    /// The length shown on the quiz's card.
    var lengthLabel: LocalizedStringResource {
        switch self {
        case .bubblePop, .higherLower, .lineUp: "^[\(questionCount) round](inflect: true)"
        case .pawPairs: "^[\(questionCount) board](inflect: true)"
        case .mysteryPet: "^[\(questionCount) mystery](inflect: true)"
        case .wordWag: "^[\(questionCount) word](inflect: true)"
        case .whosHiding: "^[\(questionCount) animal](inflect: true)"
        default: "^[\(questionCount) question](inflect: true)"
        }
    }

    /// The progress shown at the top of the quiz, counting from 1.
    func progressLabel(position: Int) -> LocalizedStringResource {
        switch self {
        case .bubblePop, .higherLower, .lineUp: "Round \(position) of \(questionCount)"
        case .pawPairs: "Board \(position) of \(questionCount)"
        case .mysteryPet: "Mystery \(position) of \(questionCount)"
        case .wordWag: "Word \(position) of \(questionCount)"
        case .whosHiding: "Animal \(position) of \(questionCount)"
        default: "Question \(position) of \(questionCount)"
        }
    }

    /// Where the best score is kept between launches.
    var bestScoreKey: String {
        "quiz.best.\(rawValue)"
    }
}
