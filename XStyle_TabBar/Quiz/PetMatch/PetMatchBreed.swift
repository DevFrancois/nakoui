import SwiftUI

/// The six breeds Which Dog Are You? can match, each one a personality as
/// much as a pedigree, with a real fact about the breed for good measure.
/// Nonisolated, like `PetSpecies`, so it can serve as a sendable ID.
nonisolated enum PetMatchBreed: CaseIterable, Comparable {
    case goldenRetriever
    case borderCollie
    case shibaInu
    case frenchBulldog
    case beagle
    case greyhound

    var name: LocalizedStringResource {
        switch self {
        case .goldenRetriever: "Golden Retriever"
        case .borderCollie: "Border Collie"
        case .shibaInu: "Shiba Inu"
        case .frenchBulldog: "French Bulldog"
        case .beagle: "Beagle"
        case .greyhound: "Greyhound"
        }
    }

    /// The breed's emblem, a nod to its personality.
    var symbol: String {
        switch self {
        case .goldenRetriever: "sun.max.fill"
        case .borderCollie: "graduationcap.fill"
        case .shibaInu: "crown.fill"
        case .frenchBulldog: "cup.and.saucer.fill"
        case .beagle: "nose.fill"
        case .greyhound: "sofa.fill"
        }
    }

    var tint: Color {
        switch self {
        case .goldenRetriever: .orange
        case .borderCollie: .blue
        case .shibaInu: .red
        case .frenchBulldog: .purple
        case .beagle: .brown
        case .greyhound: .teal
        }
    }

    /// Who you are, if this is your match.
    var summary: LocalizedStringResource {
        switch self {
        case .goldenRetriever:
            "You're sunshine on four legs: warm, loyal and always happy to see everyone. You turn strangers into friends and make any gathering better just by showing up."
        case .borderCollie:
            "You're a clever go-getter who loves a challenge and never does anything halfway. Give you a goal and it's planned, organized and done before anyone else has started."
        case .shibaInu:
            "You're cool, confident and happily your own person. You pick your friends carefully, and the lucky few get your fierce loyalty, plus a strong opinion or two."
        case .frenchBulldog:
            "You're easygoing, affectionate and full of charm. A cozy evening in, a stroll to the café and a well-earned nap: that's your perfect day."
        case .beagle:
            "Curious, cheerful and powered by snacks, you follow your nose wherever it leads. You're always the first to find the fun at a party, and the snacks."
        case .greyhound:
            "You're gentle and laid-back, happiest stretched out somewhere comfy. But when something sparks your interest, you go from zero to full speed in a heartbeat."
        }
    }

    /// A well-established fact about the real breed.
    var fact: LocalizedStringResource {
        switch self {
        case .goldenRetriever:
            "Goldens were first bred in the Scottish Highlands in the late 1800s, to fetch birds for hunters on land and in water."
        case .borderCollie:
            "Border Collies are often ranked the smartest of all dog breeds, and many still herd sheep on farms today."
        case .shibaInu:
            "The Shiba Inu is the smallest of Japan's six native dog breeds, and many are known for a dramatic yell fans call the \"Shiba scream\"."
        case .frenchBulldog:
            "Frenchies are known for their \"bat ears\", and most aren't natural swimmers, so they need a snug life jacket and a close eye near water."
        case .beagle:
            "In the US, Beagles of the \"Beagle Brigade\" sniff airport luggage for fruit, meat and plants that travelers aren't allowed to bring in."
        case .greyhound:
            "Greyhounds can sprint at up to about 70 km/h (45 mph), yet they're famous couch potatoes who love a long nap."
        }
    }

    var traits: [PetMatchTrait] {
        switch self {
        case .goldenRetriever:
            [
                PetMatchTrait(title: "Friendly", symbol: "hand.wave.fill"),
                PetMatchTrait(title: "Loyal", symbol: "heart.fill"),
                PetMatchTrait(title: "Playful", symbol: "tennisball.fill")
            ]
        case .borderCollie:
            [
                PetMatchTrait(title: "Clever", symbol: "brain.head.profile.fill"),
                PetMatchTrait(title: "Driven", symbol: "flame.fill"),
                PetMatchTrait(title: "Focused", symbol: "scope")
            ]
        case .shibaInu:
            [
                PetMatchTrait(title: "Independent", symbol: "figure.walk"),
                PetMatchTrait(title: "Dignified", symbol: "star.fill"),
                PetMatchTrait(title: "Spirited", symbol: "bolt.fill")
            ]
        case .frenchBulldog:
            [
                PetMatchTrait(title: "Easygoing", symbol: "leaf.fill"),
                PetMatchTrait(title: "Charming", symbol: "sparkles"),
                PetMatchTrait(title: "Cuddly", symbol: "heart.fill")
            ]
        case .beagle:
            [
                PetMatchTrait(title: "Curious", symbol: "magnifyingglass"),
                PetMatchTrait(title: "Foodie", symbol: "fork.knife"),
                PetMatchTrait(title: "Cheerful", symbol: "face.smiling")
            ]
        case .greyhound:
            [
                PetMatchTrait(title: "Gentle", symbol: "cloud.fill"),
                PetMatchTrait(title: "Laid-back", symbol: "moon.zzz.fill"),
                PetMatchTrait(title: "Speedy", symbol: "hare.fill")
            ]
        }
    }

    /// A line for when this breed comes a close second.
    var runnerUpNote: LocalizedStringResource {
        switch self {
        case .goldenRetriever: "You've got a sunny, social side too."
        case .borderCollie: "There's a clever go-getter in you too."
        case .shibaInu: "You've got an independent streak too."
        case .frenchBulldog: "You've got a cozy, easygoing side too."
        case .beagle: "There's a curious foodie in you too."
        case .greyhound: "You've got a laid-back side too."
        }
    }

    /// What gets shared from the results.
    var shareMessage: LocalizedStringResource {
        switch self {
        case .goldenRetriever:
            "I took Which Dog Are You? and I'm a Golden Retriever: friendly, loyal and playful! Which dog are you?"
        case .borderCollie:
            "I took Which Dog Are You? and I'm a Border Collie: clever, driven and focused! Which dog are you?"
        case .shibaInu:
            "I took Which Dog Are You? and I'm a Shiba Inu: independent, dignified and spirited! Which dog are you?"
        case .frenchBulldog:
            "I took Which Dog Are You? and I'm a French Bulldog: easygoing, charming and cuddly! Which dog are you?"
        case .beagle:
            "I took Which Dog Are You? and I'm a Beagle: curious, cheerful and always hungry! Which dog are you?"
        case .greyhound:
            "I took Which Dog Are You? and I'm a Greyhound: gentle, laid-back and secretly speedy! Which dog are you?"
        }
    }
}
