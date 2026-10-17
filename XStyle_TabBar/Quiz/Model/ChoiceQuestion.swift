import Foundation

/// A multiple-choice question for the classic quiz.
struct ChoiceQuestion: Identifiable {
    let id = UUID()
    let prompt: LocalizedStringResource
    let choices: [Choice]
    let answerIndex: Int
    let fact: LocalizedStringResource

    init(prompt: LocalizedStringResource, choices: [LocalizedStringResource], answerIndex: Int, fact: LocalizedStringResource) {
        self.prompt = prompt
        self.choices = choices.map { Choice(title: $0) }
        self.answerIndex = answerIndex
        self.fact = fact
    }

    /// Created with the question bank, so answers retain their own identity
    /// across layout changes rather than borrowing a collection position.
    struct Choice: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
    }
}
