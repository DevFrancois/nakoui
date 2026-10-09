import SwiftUI

/// The animals hiding in Who's Hiding?, kept to well-established facts.
/// Each round's first clues also fit some of the wrong choices, so the
/// glass, not just the opening clue, decides who answers early.
enum WhosHidingRounds {
    static let all: [WhosHidingRound] = [
        WhosHidingRound(
            symbol: "cat.fill",
            tint: .purple,
            reveal: "It's a cat!",
            clues: [
                "I often sleep more than half the day.",
                "My claws slide back in when I'm not using them.",
                "I purr when I'm content."
            ],
            choices: ["Dog", "Ferret", "Cat", "Hamster"],
            answerIndex: 2,
            fact: "A cat's tongue is covered in tiny backward-facing hooks that comb its fur as it grooms."
        ),
        WhosHidingRound(
            symbol: "bird.fill",
            tint: .blue,
            reveal: "It's a bird!",
            clues: [
                "I have no teeth.",
                "Some of my bones are hollow and filled with air.",
                "I'm covered in feathers."
            ],
            choices: ["Tortoise", "Chinchilla", "Ferret", "Bird"],
            answerIndex: 3,
            fact: "Budgies, often called parakeets in the US, are among the most popular pet birds, and some learn to say dozens of words."
        ),
        WhosHidingRound(
            symbol: "tortoise.fill",
            tint: .brown,
            reveal: "It's a tortoise!",
            clues: [
                "I'm cold-blooded, so I bask to warm up.",
                "I have a beak instead of teeth.",
                "My shell is part of my skeleton, so I can never leave it."
            ],
            choices: ["Hedgehog", "Tortoise", "Lizard", "Guinea pig"],
            answerIndex: 1,
            fact: "Tortoises can live a very long time: Jonathan, a giant tortoise on Saint Helena, is thought to have hatched around 1832."
        ),
        WhosHidingRound(
            symbol: "hare.fill",
            tint: .pink,
            reveal: "It's a rabbit!",
            clues: [
                "My teeth never stop growing.",
                "I thump a back foot to warn of danger.",
                "My long ears help me hear danger and stay cool."
            ],
            choices: ["Rabbit", "Guinea pig", "Hamster", "Cat"],
            answerIndex: 0,
            fact: "A happy rabbit may leap and twist in midair. Rabbit fans call it a binky."
        ),
        WhosHidingRound(
            symbol: "fish.fill",
            tint: .teal,
            reveal: "It's a fish!",
            clues: [
                "I have no eyelids, so I rest with my eyes open.",
                "I steer with my fins.",
                "I breathe through gills my whole life."
            ],
            choices: ["Frog", "Snake", "Fish", "Turtle"],
            answerIndex: 2,
            fact: "Goldfish don't have a three-second memory: studies show they can remember things for months."
        ),
        WhosHidingRound(
            symbol: "lizard.fill",
            tint: .green,
            reveal: "It's a lizard!",
            clues: [
                "I shed my skin as I grow.",
                "I'm a reptile with scaly skin.",
                "I have four legs, and some of my kind can drop their tail to escape."
            ],
            choices: ["Snake", "Lizard", "Frog", "Ferret"],
            answerIndex: 1,
            fact: "A bearded dragon can puff out and darken the spiky skin under its chin, its \"beard\", to look bigger."
        ),
        WhosHidingRound(
            symbol: "dog.fill",
            tint: .orange,
            reveal: "It's a dog!",
            clues: [
                "My sense of smell is far keener than yours.",
                "I pant to cool down.",
                "My ancestors were wolves, and I may greet you with a bark."
            ],
            choices: ["Ferret", "Guinea pig", "Cat", "Dog"],
            answerIndex: 3,
            fact: "Dogs were the first animals people domesticated, more than 14,000 years ago, long before farming began."
        )
    ]

    static let count = all.count

    /// Every animal named while the glass is still at its frostiest.
    static let maxScore = count * WhosHidingStage.frosted.points
}
