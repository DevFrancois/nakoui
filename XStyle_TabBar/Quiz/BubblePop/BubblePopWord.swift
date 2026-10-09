import Foundation

/// One word to float in a bubble, and whether it fits the round's rule.
struct BubblePopWord: Identifiable {
    let id = UUID()
    let text: LocalizedStringResource
    let isMatch: Bool
}
