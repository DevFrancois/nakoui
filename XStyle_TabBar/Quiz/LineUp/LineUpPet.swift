import SwiftUI

/// One pet to put in line, with the value it's ranked by, revealed once the
/// line-up is checked.
struct LineUpPet: Identifiable {
    let id = UUID()
    let name: LocalizedStringResource
    let symbol: String
    let tint: Color
    /// Shown after checking, such as "About 10 kg".
    let value: LocalizedStringResource
}
