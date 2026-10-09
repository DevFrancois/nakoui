import Foundation

/// The matchups for Higher or Lower. Values are typical figures from breed
/// standards and veterinary references, rounded, and every pair sits far
/// enough apart that no reasonable estimate could flip the answer.
enum HigherLowerRounds {
    static let all: [HigherLowerRound] = [
        HigherLowerRound(
            stat: .weight,
            known: .dog("Beagle", 10),
            challenger: .dog("Labrador Retriever", 30),
            fact: "About one in four Labradors carries a gene change linked to feeling hungrier, which may explain their famous love of food."
        ),
        HigherLowerRound(
            stat: .speed,
            known: .dog("Greyhound", 70),
            challenger: .sprinter("Fastest human", 45),
            fact: "For all that speed, Greyhounds are famously laid-back at home, and are often called the world's fastest couch potatoes."
        ),
        HigherLowerRound(
            stat: .lifespan,
            known: .dog("Great Dane", 8),
            challenger: .dog("Jack Russell Terrier", 13),
            fact: "Small breeds usually outlive giant ones: in a 2022 UK study of vet records, Jack Russell Terriers had the longest life expectancy of the popular breeds compared."
        ),
        HigherLowerRound(
            stat: .sleep,
            known: .human("Adult human", 8),
            challenger: .cat("Adult cat", 14),
            fact: "Cats are most active around dawn and dusk, which explains many an early-morning wake-up call."
        ),
        HigherLowerRound(
            stat: .height,
            known: .dog("Irish Wolfhound", 81),
            challenger: .dog("Border Collie", 53),
            fact: "What Border Collies lack in height, they make up for in brains: one named Chaser learned the names of more than 1,000 toys."
        ),
        HigherLowerRound(
            stat: .weight,
            known: .cat("Maine Coon", 7),
            challenger: .dog("Yorkshire Terrier", 3),
            fact: "Maine Coons are one of the largest cat breeds, and a big male can weigh more than two Yorkshire Terriers."
        ),
        HigherLowerRound(
            stat: .teeth,
            known: .dog("Adult dog", 42),
            challenger: .rabbit("Rabbit", 28),
            fact: "A rabbit's teeth never stop growing, so it needs plenty of hay to chew to keep them worn down."
        ),
        HigherLowerRound(
            stat: .heartRate,
            known: .human("Adult human", 70),
            challenger: .hamster("Hamster", 350),
            fact: "Smaller animals tend to have faster heartbeats: even at rest, a hamster's heart beats several hundred times a minute."
        ),
        HigherLowerRound(
            stat: .lifespan,
            known: .cat("House cat", 14),
            challenger: .tortoise("Pet tortoise", 50),
            fact: "With good care, many pet tortoises live 50 years or more, so some are passed down from one generation to the next."
        ),
        HigherLowerRound(
            stat: .weight,
            known: .dog("Saint Bernard", 70),
            challenger: .dog("German Shepherd", 32),
            fact: "Saint Bernards were rescue dogs in the Swiss Alps. The most famous, Barry, is credited with saving more than 40 people."
        )
    ]

    static let count = all.count
    /// One point for each matchup called right.
    static let maxScore = count
}
