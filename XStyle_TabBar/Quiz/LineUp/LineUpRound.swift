import Foundation

/// One line-up: what to order the pets by, the two ends of the line, the
/// pets in the right order, and a fact to finish on.
struct LineUpRound: Identifiable {
    let id = UUID()
    /// The order to make, such as "Lightest to heaviest".
    let title: LocalizedStringResource
    /// What's compared, such as "Typical adult weight".
    let measure: LocalizedStringResource
    let symbol: String
    /// The start of the line, such as "Lightest".
    let firstLabel: LocalizedStringResource
    let firstSymbol: String
    /// The end of the line, such as "Heaviest".
    let lastLabel: LocalizedStringResource
    let lastSymbol: String
    /// In the right order, first to last. Neighbors sit well apart, so
    /// typical variation can't swap them.
    let pets: [LineUpPet]
    let fact: LocalizedStringResource
}
