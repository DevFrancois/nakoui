import Foundation

extension HistoryItem {
    /// Placeholder history spread over the last week, newest first.
    static let samples: [HistoryItem] = {
        let now = Date.now
        func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            HistoryItem(id: 1, title: "Why Cats Knead Blankets", source: "Pet Science Weekly", kind: .article, date: hoursAgo(0.4), progress: 0.6),
            HistoryItem(id: 2, title: "Golden Retriever Learns to Skateboard", source: "Paws TV", kind: .video, date: hoursAgo(1.5), progress: 0.35),
            HistoryItem(id: 3, title: "Pet Trivia", source: "Quizz", kind: .quiz, date: hoursAgo(3)),
            HistoryItem(id: 4, title: "Our new puppy's first snow day", source: "@maya", kind: .post, date: hoursAgo(5)),
            HistoryItem(id: 5, title: "The Secret Life of House Rabbits", source: "Nako Stories", kind: .article, date: hoursAgo(26), progress: 1),
            HistoryItem(id: 6, title: "Lightning Round", source: "Quizz", kind: .quiz, date: hoursAgo(28)),
            HistoryItem(id: 7, title: "Kitten vs. Cucumber, Explained", source: "Paws TV", kind: .video, date: hoursAgo(30), progress: 1),
            HistoryItem(id: 8, title: "Adopting a senior dog changed everything", source: "@leo", kind: .post, date: hoursAgo(33)),
            HistoryItem(id: 9, title: "How Parrots Learn Words", source: "Pet Science Weekly", kind: .article, date: hoursAgo(52), progress: 0.2),
            HistoryItem(id: 10, title: "Dog or Cat?", source: "Quizz", kind: .quiz, date: hoursAgo(55)),
            HistoryItem(id: 11, title: "10 Minutes of Sleepy Otters", source: "Calm Creatures", kind: .video, date: hoursAgo(76), progress: 0.8),
            HistoryItem(id: 12, title: "Building a catio on a budget", source: "@sam", kind: .post, date: hoursAgo(98)),
            HistoryItem(id: 13, title: "What Your Dog's Tail Is Telling You", source: "Nako Stories", kind: .article, date: hoursAgo(122), progress: 1),
            HistoryItem(id: 14, title: "Best Guess", source: "Quizz", kind: .quiz, date: hoursAgo(140)),
            HistoryItem(id: 15, title: "Hamster Obstacle Course Finale", source: "Paws TV", kind: .video, date: hoursAgo(150), progress: 0.5)
        ]
    }()
}
