import Foundation

/// The breeds to unscramble, alternating dogs and cats and growing longer.
/// Words stop at seven letters so a word's tiles fit on one row even on the
/// narrowest iPhone; longer ones would wrap onto a second row.
enum WordWagRounds {
    static let all: [WordWagPuzzle] = [
        WordWagPuzzle(
            word: "CORGI",
            species: .dog,
            clue: "Short legs, big ears, and a royal favorite.",
            fact: "Queen Elizabeth II owned at least 30 Pembroke Welsh Corgis, many descended from Susan, her 18th-birthday present."
        ),
        WordWagPuzzle(
            word: "SPHYNX",
            species: .cat,
            clue: "A hairless cat that loves a warm lap.",
            fact: "Sphynx cats aren't fully hairless: many have a fine peach fuzz, and their skin is often likened to warm suede."
        ),
        WordWagPuzzle(
            word: "BEAGLE",
            species: .dog,
            clue: "A merry scent hound, just like Snoopy.",
            fact: "In the U.S., a \"Beagle Brigade\" sniffs travelers' luggage at airports for forbidden food."
        ),
        WordWagPuzzle(
            word: "BENGAL",
            species: .cat,
            clue: "A cat whose spots or marbling give it a wild, leopard-like look.",
            fact: "Bengals come from crosses between house cats and the Asian leopard cat, and many love playing in water."
        ),
        WordWagPuzzle(
            word: "POODLE",
            species: .dog,
            clue: "A curly coat, a clever mind, and sizes from toy to standard.",
            fact: "Poodles were bred as water retrievers, most likely in Germany, though France claims them too. Their name comes from the German \"pudeln\", to splash about."
        ),
        WordWagPuzzle(
            word: "PERSIAN",
            species: .cat,
            clue: "A long-haired cat with a round face, a short nose and a calm nature.",
            fact: "A Persian's long coat needs combing almost every day to keep it from tangling and matting."
        ),
        WordWagPuzzle(
            word: "SAMOYED",
            species: .dog,
            clue: "A fluffy white sled dog with a famous smile.",
            fact: "Samoyeds are named after the Samoyedic peoples of Siberia, who bred them to herd reindeer and pull sleds."
        ),
        WordWagPuzzle(
            word: "RAGDOLL",
            species: .cat,
            clue: "A big, blue-eyed, laid-back cat named after a floppy toy.",
            fact: "Ragdoll kittens are born almost white; their darker points fill in over their first few years."
        )
    ]

    static let count = all.count
    /// Points for solving a word without the hint.
    static let pointsPerWord = 2
    /// What the hint takes off a solve.
    static let hintCost = 1
    static let maxScore = count * pointsPerWord
}
