import Foundation

/// The boards of one Paw Pairs game, kept to well-established names.
enum PawPairsRounds {
    static let all: [PawPairsBoard] = [
        PawPairsBoard(
            title: "Homelands",
            prompt: "Match each breed to the place it comes from.",
            symbol: "map.fill",
            pairs: [
                PawPairsPair(
                    PawPairsFace("Shiba Inu", symbol: "dog.fill"),
                    PawPairsFace("Japan", symbol: "globe.asia.australia.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Siamese", symbol: "cat.fill"),
                    PawPairsFace("Thailand", symbol: "globe.asia.australia.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Chihuahua", symbol: "dog.fill"),
                    PawPairsFace("Mexico", symbol: "globe.americas.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Bernese Mountain Dog", symbol: "dog.fill"),
                    PawPairsFace("Switzerland", symbol: "globe.europe.africa.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Pembroke Welsh Corgi", symbol: "dog.fill"),
                    PawPairsFace("Wales", symbol: "globe.europe.africa.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Maine Coon", symbol: "cat.fill"),
                    PawPairsFace("United States", symbol: "globe.americas.fill")
                )
            ],
            fact: "The Chihuahua is named after a state in Mexico, and the Bernese Mountain Dog after the Swiss canton of Bern."
        ),
        PawPairsBoard(
            title: "Baby Names",
            prompt: "Match each animal to a name for its young.",
            symbol: "stroller.fill",
            pairs: [
                PawPairsPair(
                    PawPairsFace("Dog", symbol: "dog.fill"),
                    PawPairsFace("Puppy", symbol: "teddybear.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Cat", symbol: "cat.fill"),
                    PawPairsFace("Kitten", symbol: "teddybear.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Horse", symbol: "figure.equestrian.sports"),
                    PawPairsFace("Foal", symbol: "teddybear.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Goat", symbol: "mountain.2.fill"),
                    PawPairsFace("Kid", symbol: "teddybear.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Duck", symbol: "bird.fill"),
                    PawPairsFace("Duckling", symbol: "teddybear.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Fish", symbol: "fish.fill"),
                    PawPairsFace("Fry", symbol: "teddybear.fill")
                )
            ],
            fact: "A horse is usually called a foal until it's a year old, and a yearling in its second year."
        ),
        PawPairsBoard(
            title: "Group Names",
            prompt: "Match each animal to a name for a group of them.",
            symbol: "quote.bubble.fill",
            pairs: [
                PawPairsPair(
                    PawPairsFace("Cats", symbol: "cat.fill"),
                    PawPairsFace("Clowder", symbol: "circle.hexagongrid.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Kittens", symbol: "cat.fill"),
                    PawPairsFace("Kindle", symbol: "circle.hexagongrid.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Dogs", symbol: "dog.fill"),
                    PawPairsFace("Pack", symbol: "circle.hexagongrid.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Ferrets", symbol: "pawprint.fill"),
                    PawPairsFace("Business", symbol: "circle.hexagongrid.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Parrots", symbol: "bird.fill"),
                    PawPairsFace("Pandemonium", symbol: "circle.hexagongrid.fill")
                ),
                PawPairsPair(
                    PawPairsFace("Owls", symbol: "bird.fill"),
                    PawPairsFace("Parliament", symbol: "circle.hexagongrid.fill")
                )
            ],
            fact: "This kindle isn't about fire: it comes from a medieval word for offspring, which suits a group of kittens."
        )
    ]

    static let count = all.count

    /// One point per board cleared within par.
    static let maxScore = count
}
