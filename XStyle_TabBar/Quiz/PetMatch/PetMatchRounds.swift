import Foundation

/// The questions for Which Dog Are You? Each has four answers, and each
/// answer suits one breed best and sometimes a second a little. The weights
/// are balanced so random answers land on every breed about equally often,
/// and leaning toward any breed's answers makes it the clear winner.
enum PetMatchRounds {
    static let all: [PetMatchQuestion] = [
        PetMatchQuestion(
            prompt: "Your ideal Saturday?",
            symbol: "sun.max.fill",
            answers: [
                PetMatchAnswer("Park with friends", symbol: "person.3.fill", suits: .goldenRetriever, alsoSuits: .beagle),
                PetMatchAnswer("Learn a new trick", symbol: "puzzlepiece.fill", suits: .borderCollie),
                PetMatchAnswer("Brunch in the city", symbol: "cup.and.saucer.fill", suits: .frenchBulldog, alsoSuits: .shibaInu),
                PetMatchAnswer("Nap, then a sprint", symbol: "sofa.fill", suits: .greyhound, alsoSuits: .frenchBulldog)
            ]
        ),
        PetMatchQuestion(
            prompt: "Pick a snack",
            symbol: "fork.knife",
            answers: [
                PetMatchAnswer("Anything. Everything.", symbol: "takeoutbag.and.cup.and.straw.fill", suits: .beagle, alsoSuits: .goldenRetriever),
                PetMatchAnswer("Sushi, if it's perfect", symbol: "fish.fill", suits: .shibaInu, alsoSuits: .frenchBulldog),
                PetMatchAnswer("Energy bar, on the go", symbol: "bolt.fill", suits: .borderCollie, alsoSuits: .greyhound),
                PetMatchAnswer("Popcorn on the couch", symbol: "popcorn.fill", suits: .frenchBulldog, alsoSuits: .greyhound)
            ]
        ),
        PetMatchQuestion(
            prompt: "How do you greet a stranger?",
            symbol: "hand.wave.fill",
            answers: [
                PetMatchAnswer("Instant best friends", symbol: "heart.fill", suits: .goldenRetriever, alsoSuits: .frenchBulldog),
                PetMatchAnswer("A polite nod from afar", symbol: "hand.raised.fill", suits: .shibaInu, alsoSuits: .greyhound),
                PetMatchAnswer("Ask a hundred questions", symbol: "questionmark.bubble.fill", suits: .beagle, alsoSuits: .borderCollie),
                PetMatchAnswer("A sleepy wave", symbol: "zzz", suits: .greyhound, alsoSuits: .shibaInu)
            ]
        ),
        PetMatchQuestion(
            prompt: "Pick a dream vacation",
            symbol: "airplane",
            answers: [
                PetMatchAnswer("Mountain hike", symbol: "mountain.2.fill", suits: .borderCollie, alsoSuits: .beagle),
                PetMatchAnswer("Street food tour", symbol: "map.fill", suits: .beagle, alsoSuits: .frenchBulldog),
                PetMatchAnswer("Beach with the gang", symbol: "beach.umbrella.fill", suits: .goldenRetriever, alsoSuits: .greyhound),
                PetMatchAnswer("A quiet cabin, solo", symbol: "house.lodge.fill", suits: .shibaInu, alsoSuits: .greyhound)
            ]
        ),
        PetMatchQuestion(
            prompt: "Your friends call you…",
            symbol: "person.2.fill",
            answers: [
                PetMatchAnswer("The sunshine", symbol: "sun.max.fill", suits: .goldenRetriever),
                PetMatchAnswer("The overachiever", symbol: "trophy.fill", suits: .borderCollie),
                PetMatchAnswer("The trendsetter", symbol: "sparkles", suits: .frenchBulldog, alsoSuits: .shibaInu),
                PetMatchAnswer("The chill one", symbol: "leaf.fill", suits: .greyhound, alsoSuits: .frenchBulldog)
            ]
        ),
        PetMatchQuestion(
            prompt: "Pick a superpower",
            symbol: "wand.and.stars",
            answers: [
                PetMatchAnswer("Super speed", symbol: "hare.fill", suits: .greyhound, alsoSuits: .borderCollie),
                PetMatchAnswer("Read minds", symbol: "brain.head.profile.fill", suits: .borderCollie, alsoSuits: .goldenRetriever),
                PetMatchAnswer("Find any snack, anywhere", symbol: "nose.fill", suits: .beagle, alsoSuits: .frenchBulldog),
                PetMatchAnswer("Invisibility", symbol: "eye.slash.fill", suits: .shibaInu, alsoSuits: .greyhound)
            ]
        ),
        PetMatchQuestion(
            prompt: "It's raining. What's the plan?",
            symbol: "cloud.rain.fill",
            answers: [
                PetMatchAnswer("Puddle jumping!", symbol: "drop.fill", suits: .goldenRetriever, alsoSuits: .beagle),
                PetMatchAnswer("Blanket burrito nap", symbol: "bed.double.fill", suits: .frenchBulldog, alsoSuits: .greyhound),
                PetMatchAnswer("Read by the window", symbol: "book.fill", suits: .shibaInu, alsoSuits: .borderCollie),
                PetMatchAnswer("Raid the kitchen", symbol: "refrigerator.fill", suits: .beagle, alsoSuits: .frenchBulldog)
            ]
        )
    ]

    static let count = all.count
}
