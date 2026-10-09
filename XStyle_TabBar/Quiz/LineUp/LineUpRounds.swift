import SwiftUI

/// The line-ups for one game, kept to well-established figures. Each lists
/// its pets in the right order; the game shuffles them.
enum LineUpRounds {
    static let all: [LineUpRound] = [
        LineUpRound(
            title: "Lightest to heaviest",
            measure: "Typical adult weight",
            symbol: "scalemass.fill",
            firstLabel: "Lightest",
            firstSymbol: "balloon.fill",
            lastLabel: "Heaviest",
            lastSymbol: "dumbbell.fill",
            pets: [
                LineUpPet(name: "Chihuahua", symbol: "dog.fill", tint: .pink, value: "About 1.5 to 3 kg"),
                LineUpPet(name: "Beagle", symbol: "dog.fill", tint: .brown, value: "About 9 to 14 kg"),
                LineUpPet(name: "Labrador Retriever", symbol: "dog.fill", tint: .orange, value: "About 25 to 36 kg"),
                LineUpPet(name: "Great Dane", symbol: "dog.fill", tint: .indigo, value: "About 50 to 80 kg")
            ],
            fact: "A big Great Dane can weigh as much as 30 Chihuahuas."
        ),
        LineUpRound(
            title: "Fewest to most teeth",
            measure: "Adult teeth",
            symbol: "mouth.fill",
            firstLabel: "Fewest",
            firstSymbol: "minus.circle.fill",
            lastLabel: "Most",
            lastSymbol: "plus.circle.fill",
            pets: [
                LineUpPet(name: "Hamster", symbol: "pawprint.fill", tint: .brown, value: "16 teeth"),
                LineUpPet(name: "Guinea Pig", symbol: "pawprint.fill", tint: .pink, value: "20 teeth"),
                LineUpPet(name: "Cat", symbol: "cat.fill", tint: .purple, value: "30 teeth"),
                LineUpPet(name: "Dog", symbol: "dog.fill", tint: .orange, value: "42 teeth")
            ],
            fact: "A hamster's front teeth never stop growing, and neither do any of a guinea pig's, so both need plenty to chew on."
        ),
        LineUpRound(
            title: "Least to most sleep",
            measure: "Typical sleep per day",
            symbol: "bed.double.fill",
            firstLabel: "Least sleep",
            firstSymbol: "sun.max.fill",
            lastLabel: "Most sleep",
            lastSymbol: "moon.zzz.fill",
            pets: [
                LineUpPet(name: "Horse", symbol: "figure.equestrian.sports", tint: .indigo, value: "About 2 to 5 hours"),
                LineUpPet(name: "You", symbol: "person.fill", tint: .blue, value: "7 to 9 hours for adults"),
                LineUpPet(name: "Adult Cat", symbol: "cat.fill", tint: .purple, value: "12 to 16 hours"),
                LineUpPet(name: "Puppy", symbol: "dog.fill", tint: .orange, value: "18 to 20 hours")
            ],
            fact: "Horses can doze standing up by locking their legs, but they have to lie down for REM, or dreaming, sleep."
        ),
        LineUpRound(
            title: "Shortest to longest life",
            measure: "Typical lifespan",
            symbol: "hourglass",
            firstLabel: "Shortest",
            firstSymbol: "timer",
            lastLabel: "Longest",
            lastSymbol: "infinity",
            pets: [
                LineUpPet(name: "Pet Rat", symbol: "pawprint.fill", tint: .pink, value: "About 2 to 3 years"),
                LineUpPet(name: "Rabbit", symbol: "hare.fill", tint: .gray, value: "About 8 to 12 years"),
                LineUpPet(name: "Cat", symbol: "cat.fill", tint: .purple, value: "About 15 years"),
                LineUpPet(name: "Tortoise", symbol: "tortoise.fill", tint: .green, value: "Often over 50 years")
            ],
            fact: "The oldest cat on record, Creme Puff, lived to 38."
        ),
        LineUpRound(
            title: "Slowest to fastest heartbeat",
            measure: "Resting heart rate",
            symbol: "heart.fill",
            firstLabel: "Slowest",
            firstSymbol: "tortoise.fill",
            lastLabel: "Fastest",
            lastSymbol: "hare.fill",
            pets: [
                LineUpPet(name: "Horse", symbol: "figure.equestrian.sports", tint: .indigo, value: "About 30 to 40 beats a minute"),
                LineUpPet(name: "Large Dog", symbol: "dog.fill", tint: .orange, value: "About 60 to 100 beats a minute"),
                LineUpPet(name: "Cat", symbol: "cat.fill", tint: .purple, value: "About 120 to 220 beats a minute"),
                LineUpPet(name: "Hamster", symbol: "pawprint.fill", tint: .brown, value: "About 300 to 500 beats a minute")
            ],
            fact: "Smaller animals tend to have faster hearts: a hamster's can beat several times a second."
        ),
        LineUpRound(
            title: "Longest ago to most recent",
            measure: "When each was domesticated",
            symbol: "clock.arrow.circlepath",
            firstLabel: "Longest ago",
            firstSymbol: "fossil.shell.fill",
            lastLabel: "Most recent",
            lastSymbol: "sparkles",
            pets: [
                LineUpPet(name: "Dog", symbol: "dog.fill", tint: .orange, value: "Over 14,000 years ago"),
                LineUpPet(name: "Cat", symbol: "cat.fill", tint: .purple, value: "Several thousand years ago"),
                LineUpPet(name: "Goldfish", symbol: "fish.fill", tint: .cyan, value: "Over 1,000 years ago"),
                LineUpPet(name: "Syrian Hamster", symbol: "pawprint.fill", tint: .brown, value: "Starting in 1930")
            ],
            fact: "Most pet Syrian hamsters descend from a single litter found near Aleppo in 1930."
        )
    ]

    static let count = all.count
    /// One point for every pet in its right place.
    static let maxScore = all.reduce(0) { $0 + $1.pets.count }
}
