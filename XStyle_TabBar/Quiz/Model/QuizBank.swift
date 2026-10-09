import Foundation

/// The questions for every quiz. Placeholder content until real quizzes
/// arrive from a server, kept to well-established pet facts.
enum QuizBank {
    static let choiceQuestions: [ChoiceQuestion] = [
        ChoiceQuestion(
            prompt: "How many teeth does an adult dog have?",
            choices: ["28", "32", "42", "46"],
            answerIndex: 2,
            fact: "Puppies have 28 baby teeth, replaced by 42 adult teeth by about seven months."
        ),
        ChoiceQuestion(
            prompt: "What is a group of cats called?",
            choices: ["A pack", "A clowder", "A pride", "A herd"],
            answerIndex: 1,
            fact: "A group of kittens has its own name too: a kindle."
        ),
        ChoiceQuestion(
            prompt: "Which is the smallest dog breed?",
            choices: ["Pomeranian", "Chihuahua", "Yorkshire Terrier", "Maltese"],
            answerIndex: 1,
            fact: "Many Chihuahuas weigh under 3 kg as adults."
        ),
        ChoiceQuestion(
            prompt: "How many toes does a cat usually have?",
            choices: ["16", "18", "20", "22"],
            answerIndex: 1,
            fact: "Five on each front paw and four on each back paw. Cats with extra toes are called polydactyl."
        ),
        ChoiceQuestion(
            prompt: "Which is a dog's strongest sense?",
            choices: ["Sight", "Hearing", "Smell", "Taste"],
            answerIndex: 2,
            fact: "A dog's nose has up to 300 million scent receptors, against about 6 million in ours."
        ),
        ChoiceQuestion(
            prompt: "Which taste can't cats detect?",
            choices: ["Salty", "Sour", "Bitter", "Sweet"],
            answerIndex: 3,
            fact: "Cats lack a working gene for the sweet taste receptor."
        ),
        ChoiceQuestion(
            prompt: "Which dog breed has a blue-black tongue?",
            choices: ["Chow Chow", "Beagle", "Boxer", "Poodle"],
            answerIndex: 0,
            fact: "The Chinese Shar-Pei shares the trait."
        ),
        ChoiceQuestion(
            prompt: "About how long does a cat's pregnancy last?",
            choices: ["3 weeks", "9 weeks", "4 months", "6 months"],
            answerIndex: 1,
            fact: "About 63 to 67 days, close to a dog's."
        )
    ]

    static let speciesStatements: [SpeciesStatement] = [
        SpeciesStatement(
            text: "Has retractable claws",
            species: .cat,
            fact: "Cats keep their claws sheathed to keep them sharp; a dog's claws are always out."
        ),
        SpeciesStatement(
            text: "Was domesticated from the wolf",
            species: .dog,
            fact: "Dogs descend from ancient wolves, tamed at least 15,000 years ago."
        ),
        SpeciesStatement(
            text: "Its wild ancestor is the African wildcat",
            species: .cat,
            fact: "Cats began living alongside farmers in the Near East about 10,000 years ago."
        ),
        SpeciesStatement(
            text: "Purrs when content",
            species: .cat,
            fact: "Cats also purr when stressed or hurt, which may help them heal."
        ),
        SpeciesStatement(
            text: "Can be trained to herd sheep",
            species: .dog,
            fact: "Border Collies steer a flock with a fixed stare known as \"the eye\"."
        ),
        SpeciesStatement(
            text: "Lands on its feet thanks to a righting reflex",
            species: .cat,
            fact: "Kittens start developing the reflex at about three to four weeks old."
        ),
        SpeciesStatement(
            text: "Pants to cool down",
            species: .dog,
            fact: "Dogs have few sweat glands, mostly in their paw pads, so panting does most of the cooling."
        ),
        SpeciesStatement(
            text: "Kneads soft surfaces with its paws",
            species: .cat,
            fact: "Kneading starts in kittenhood, when kittens knead to get milk flowing."
        ),
        SpeciesStatement(
            text: "Has about 300 million scent receptors",
            species: .dog,
            fact: "Scent hounds like the Bloodhound can follow trails that are days old."
        ),
        SpeciesStatement(
            text: "Can turn each ear about 180 degrees",
            species: .cat,
            fact: "Each ear is moved by 32 muscles."
        )
    ]

    static let trueFalseStatements: [TrueFalseStatement] = [
        TrueFalseStatement(
            text: "Cats sleep 12 to 16 hours a day.",
            isTrue: true,
            fact: "Kittens and older cats often sleep even more."
        ),
        TrueFalseStatement(
            text: "Dogs see only in black and white.",
            isTrue: false,
            fact: "Dogs see blues and yellows; reds and greens look grayish to them."
        ),
        TrueFalseStatement(
            text: "Chocolate is toxic to dogs.",
            isTrue: true,
            fact: "It contains theobromine, which dogs break down very slowly."
        ),
        TrueFalseStatement(
            text: "Dalmatian puppies are born with spots.",
            isTrue: false,
            fact: "They're born white; their spots appear after about two weeks."
        ),
        TrueFalseStatement(
            text: "Most adult cats digest milk easily.",
            isTrue: false,
            fact: "Most adult cats are lactose intolerant, so milk can upset their stomach."
        ),
        TrueFalseStatement(
            text: "A dog's nose print is unique, like a fingerprint.",
            isTrue: true,
            fact: "The ridges and patterns on each nose are one of a kind."
        ),
        TrueFalseStatement(
            text: "Cats have more bones than humans.",
            isTrue: true,
            fact: "Cats have around 230 bones; adult humans have 206."
        ),
        TrueFalseStatement(
            text: "The Basenji is known as the barkless dog.",
            isTrue: true,
            fact: "Instead of barking, it makes a yodel-like sound called a baroo."
        ),
        TrueFalseStatement(
            text: "Grapes are a safe treat for dogs.",
            isTrue: false,
            fact: "Grapes and raisins can cause kidney failure in dogs."
        ),
        TrueFalseStatement(
            text: "A dog's sense of smell is about twice as strong as ours.",
            isTrue: false,
            fact: "Estimates put it 10,000 to 100,000 times stronger."
        ),
        TrueFalseStatement(
            text: "Cats have whiskers on the backs of their front legs.",
            isTrue: true,
            fact: "These carpal whiskers help them feel prey they're holding."
        ),
        TrueFalseStatement(
            text: "Dogs sweat mainly through their tongues.",
            isTrue: false,
            fact: "They sweat a little through their paw pads; panting is how they cool down."
        )
    ]

    static let estimateQuestions: [EstimateQuestion] = [
        EstimateQuestion(
            prompt: "How many hours a day does an adult cat sleep, on average?",
            range: 0...24,
            step: 1,
            answer: 15,
            tolerance: 2,
            unit: "hours",
            fact: "Most cats sleep 12 to 16 hours a day."
        ),
        EstimateQuestion(
            prompt: "How many muscles move each of a cat's ears?",
            range: 0...60,
            step: 1,
            answer: 32,
            tolerance: 4,
            unit: "muscles",
            fact: "Humans have just six muscles around each ear."
        ),
        EstimateQuestion(
            prompt: "How fast can a Greyhound run?",
            range: 0...100,
            step: 1,
            answer: 72,
            tolerance: 8,
            unit: "km/h",
            fact: "Greyhounds are the fastest dog breed, reaching about 72 km/h in a sprint."
        ),
        EstimateQuestion(
            prompt: "How many dog breeds does the FCI recognize?",
            range: 0...500,
            step: 10,
            answer: 360,
            tolerance: 40,
            unit: "breeds",
            fact: "The Fédération Cynologique Internationale recognizes around 360 breeds."
        ),
        EstimateQuestion(
            prompt: "What's a cat's normal resting heart rate?",
            range: 60...300,
            step: 5,
            answer: 180,
            tolerance: 30,
            unit: "beats per minute",
            fact: "A healthy cat's heart beats about 140 to 220 times a minute."
        ),
        EstimateQuestion(
            prompt: "How many years does a dog live, on average?",
            range: 0...25,
            step: 1,
            answer: 12,
            tolerance: 2,
            unit: "years",
            fact: "It depends on size: small breeds often reach 14 or more, giant breeds closer to 8."
        )
    ]
}
