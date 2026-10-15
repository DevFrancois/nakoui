import Foundation

/// Something the user opened.
struct HistoryItem: Identifiable {
    let id: Int
    let title: String
    /// Where it came from: an author, a channel or a quiz category.
    let source: String
    let kind: HistoryKind
    let date: Date
    /// How far through it the user got, for videos and articles.
    var progress: Double?
}
