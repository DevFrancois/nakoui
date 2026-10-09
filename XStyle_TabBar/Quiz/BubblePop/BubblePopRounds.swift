import Foundation

/// The Bubble Pop rounds, easiest first: each has a rule, five words that
/// fit it, and a handful of decoys, some of them tricky. Kept to
/// well-established pet facts.
enum BubblePopRounds {
    static let all: [BubblePopRound] = [
        BubblePopRound(
            rule: "Pop every cat breed!",
            symbol: "cat.fill",
            matches: ["Maine Coon", "Siamese", "Sphynx", "Ragdoll", "Birman"],
            decoys: ["Beagle", "Havanese", "Pug", "Whippet"],
            fact: "The Sphynx isn't truly hairless: many have a fine, barely visible down that makes their skin feel like a peach."
        ),
        BubblePopRound(
            rule: "Pop the pets that are mammals!",
            symbol: "hare.fill",
            matches: ["Hamster", "Rabbit", "Ferret", "Guinea Pig", "Chinchilla"],
            decoys: ["Gecko", "Goldfish", "Budgie", "Axolotl", "Tortoise"],
            fact: "Axolotls are amphibians, not fish, and almost always keep their feathery gills their whole lives."
        ),
        BubblePopRound(
            rule: "Pop the sounds a cat makes!",
            symbol: "waveform",
            matches: ["Purr", "Meow", "Hiss", "Trill", "Chirp"],
            decoys: ["Woof", "Neigh", "Quack", "Baroo"],
            fact: "Adult cats rarely meow at each other: meowing is mostly how they talk to people."
        ),
        BubblePopRound(
            rule: "Pop the foods that are toxic to dogs!",
            symbol: "exclamationmark.triangle.fill",
            matches: ["Chocolate", "Grapes", "Onion", "Xylitol", "Macadamia nuts"],
            decoys: ["Carrot", "Blueberries", "Pumpkin", "Plain rice", "Green beans"],
            fact: "Xylitol, a sweetener in some sugar-free gum, can make a dog's blood sugar drop dangerously fast."
        ),
        BubblePopRound(
            rule: "Pop the herding dogs!",
            symbol: "dog.fill",
            matches: ["Border Collie", "Corgi", "Sheltie", "German Shepherd", "Australian Shepherd"],
            decoys: ["Labrador", "Chihuahua", "Greyhound", "Bulldog", "Husky"],
            fact: "Corgis were bred to herd cattle, nipping at their heels and staying low enough to dodge the kicks."
        ),
        BubblePopRound(
            rule: "Pop the breeds from Germany!",
            symbol: "globe.europe.africa.fill",
            matches: ["Dachshund", "Rottweiler", "Great Dane", "Weimaraner", "Boxer"],
            decoys: ["Dalmatian", "Shih Tzu", "Basenji", "Samoyed", "French Bulldog"],
            fact: "Despite its name, the Great Dane comes from Germany, where it was bred to hunt wild boar."
        )
    ]

    static let count = all.count
    /// One point for each round cleared.
    static let maxScore = count
}
