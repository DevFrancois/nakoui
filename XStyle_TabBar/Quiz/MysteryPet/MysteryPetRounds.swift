import Foundation

/// The mystery breeds for Who Am I?, and how its points work: a right answer
/// on the first clue earns three, on the second two, and on the third or
/// fourth one. Kept to well-established breed facts.
enum MysteryPetRounds {
    /// What a right answer earns on the first clue.
    static let maxPoints = 3

    static let all: [MysteryPetBreed] = [
        MysteryPetBreed(
            species: .dog,
            clues: [
                "I was bred in Germany to follow badgers right into their burrows.",
                "My bark is surprisingly loud for my size, so hunters could hear me underground.",
                "I come in three coats: smooth, wirehaired and longhaired.",
                "Lots of people call me a wiener dog or a sausage dog."
            ],
            choices: ["Basset Hound", "Dachshund", "Beagle", "Pembroke Welsh Corgi"],
            answerIndex: 1,
            fact: "Waldi, the mascot of the 1972 Munich Games and the first official Olympic mascot, was a Dachshund."
        ),
        MysteryPetBreed(
            species: .cat,
            clues: [
                "I often chat in little chirps and trills rather than meows.",
                "My big, tufted paws work like snowshoes.",
                "A silly legend says I'm half raccoon. I'm not, but it's one story behind my name.",
                "I'm the official state cat of Maine."
            ],
            choices: ["Norwegian Forest Cat", "Ragdoll", "Siberian", "Maine Coon"],
            answerIndex: 3,
            fact: "A Maine Coon named Stewie once held the record for the longest domestic cat: about 123 cm from nose to tail tip."
        ),
        MysteryPetBreed(
            species: .dog,
            clues: [
                "Without a job to do, I might try to herd children, cats or even cars.",
                "I'm often ranked the cleverest dog breed of all.",
                "I crouch low and stare sheep down to steer the flock.",
                "I was bred near the border between England and Scotland."
            ],
            choices: ["Border Collie", "Australian Shepherd", "Shetland Sheepdog", "Rough Collie"],
            answerIndex: 0,
            fact: "A Border Collie named Chaser learned the names of more than 1,000 toys and could fetch them by name."
        ),
        MysteryPetBreed(
            species: .cat,
            clues: [
                "Many of my ancestors had crossed eyes and a kink in their tail.",
                "I'm famously chatty, and I'll happily talk back to you.",
                "My fur is darker where my body is cooler: my ears, face, paws and tail.",
                "I'm named after Siam, the old name for Thailand."
            ],
            choices: ["Birman", "Burmese", "Siamese", "Ragdoll"],
            answerIndex: 2,
            fact: "Siamese kittens are born almost white; their dark points fill in as they grow."
        ),
        MysteryPetBreed(
            species: .dog,
            clues: [
                "My famous old job was trotting beside horse-drawn carriages to guard them.",
                "Firehouses kept me to run ahead of their horse-drawn engines.",
                "I'm born pure white, and my spots appear as I grow.",
                "101 of my kind starred in a famous Disney film."
            ],
            choices: ["Great Dane", "English Pointer", "Bull Terrier", "Dalmatian"],
            answerIndex: 3,
            fact: "No two Dalmatians have the same spots, which are usually black or liver brown."
        ),
        MysteryPetBreed(
            species: .cat,
            clues: [
                "My breed's story began in Canada in the 1960s, with one unusual kitten.",
                "I feel warm and soft, like suede, when you stroke me.",
                "I need regular baths, because oil builds up on my skin.",
                "I'm famous for having almost no fur at all."
            ],
            choices: ["Devon Rex", "Sphynx", "Cornish Rex", "Oriental Shorthair"],
            answerIndex: 1,
            fact: "Sphynx cats aren't truly bald: most are covered in a fine down that feels like peach fuzz."
        )
    ]

    static let count = all.count
    static let maxScore = count * maxPoints

    /// What a right answer earns once `clues` clues are showing: one paw
    /// fewer for each extra clue, never below one.
    static func points(afterClues clues: Int) -> Int {
        max(1, maxPoints + 1 - clues)
    }
}
