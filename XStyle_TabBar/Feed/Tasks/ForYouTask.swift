import SwiftUI

/// Something the For you feed asks the user to do, shown as a card in the
/// task stack and in the task sheet.
struct ForYouTask: Identifiable {
    let id: String
    /// The small uppercase heading above the card's divider.
    let category: LocalizedStringResource
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let symbol: String
    let tint: Color
    /// The sheet's button that completes the task.
    let actionTitle: LocalizedStringResource
}

extension ForYouTask {
    static let samples = [
        ForYouTask(
            id: "profile",
            category: "Getting Started",
            title: "Finish Your Profile",
            message: "Add a photo and a short bio so people know who's behind your bookmarks.",
            symbol: "person.crop.circle.badge.plus",
            tint: .blue,
            actionTitle: "Edit Profile"
        ),
        ForYouTask(
            id: "notifications",
            category: "Notifications",
            title: "Choose Your Alerts",
            message: "Pick which updates reach you, and when, so nothing important slips by.",
            symbol: "bell.badge",
            tint: .orange,
            actionTitle: "Choose Alerts"
        ),
        ForYouTask(
            id: "privacy",
            category: "Privacy Checklist",
            title: "Check Who Sees Your Likes",
            message: "Review who can see your likes and bookmarks before you share more.",
            symbol: "lock.shield",
            tint: .green,
            actionTitle: "Review"
        )
    ]
}
