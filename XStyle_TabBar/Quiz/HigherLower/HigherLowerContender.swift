import SwiftUI

/// One side of a matchup: who it is, how it's drawn, and its typical value
/// for the round's stat, in that stat's unit.
struct HigherLowerContender {
    let name: LocalizedStringResource
    let symbol: String
    let tint: Color
    let value: Double

    static func dog(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: PetSpecies.dog.symbol, tint: PetSpecies.dog.tint, value: value)
    }

    static func cat(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: PetSpecies.cat.symbol, tint: PetSpecies.cat.tint, value: value)
    }

    static func rabbit(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: "hare.fill", tint: .brown, value: value)
    }

    static func hamster(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        // Golden orange: yellow all but vanishes on light glass.
        HigherLowerContender(name: name, symbol: "pawprint.fill", tint: .orange, value: value)
    }

    static func tortoise(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: "tortoise.fill", tint: .green, value: value)
    }

    /// People join in now and then, so players can see how they measure up.
    static func human(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: "figure.stand", tint: .blue, value: value)
    }

    static func sprinter(_ name: LocalizedStringResource, _ value: Double) -> HigherLowerContender {
        HigherLowerContender(name: name, symbol: "figure.run", tint: .blue, value: value)
    }
}
