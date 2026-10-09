import Foundation

/// A multiple-choice question for the classic quiz.
struct ChoiceQuestion: Identifiable {
    let id = UUID()
    let prompt: LocalizedStringResource
    let choices: [LocalizedStringResource]
    let answerIndex: Int
    let fact: LocalizedStringResource
}
