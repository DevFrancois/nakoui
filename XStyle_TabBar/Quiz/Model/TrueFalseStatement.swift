import Foundation

/// A claim to judge in the lightning round.
struct TrueFalseStatement: Identifiable {
    let id = UUID()
    let text: LocalizedStringResource
    let isTrue: Bool
    let fact: LocalizedStringResource
}
