import SwiftUI

/// The sheets the For you feed's cards open: the What's New card and the four
/// tiles below it.
enum ForYouDestination: String, Identifiable {
    case whatsNew
    case first
    case second
    case third
    case fourth

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .whatsNew: "What's New"
        case .first: "First"
        case .second: "Second"
        case .third: "Third"
        case .fourth: "Fourth"
        }
    }

    var tint: Color {
        switch self {
        case .whatsNew: .blue
        case .first, .third: .purple
        case .second, .fourth: .teal
        }
    }

    var items: [ForYouDetailItem] {
        switch self {
        case .whatsNew: [
            ForYouDetailItem(text: "Swipe between tabs, or tap a chip to jump straight to one.", symbol: "rectangle.stack"),
            ForYouDetailItem(
                text: AppFeatures.sideMenuEnabled
                    ? "Drag from the left edge to open the side menu."
                    : "Open Scan to read a product barcode.",
                symbol: AppFeatures.sideMenuEnabled ? "sidebar.left" : "barcode.viewfinder"
            ),
            ForYouDetailItem(text: "The top menu tucks away as you scroll down.", symbol: "arrow.up.and.down")
        ]
        case .first: [
            ForYouDetailItem(text: "Placeholder text for the first card's opening line.", symbol: "star"),
            ForYouDetailItem(text: "A second placeholder line with a little more detail.", symbol: "text.alignleft"),
            ForYouDetailItem(text: "A closing placeholder line.", symbol: "checkmark.circle")
        ]
        case .second: [
            ForYouDetailItem(text: "Placeholder text describing the second card.", symbol: "leaf"),
            ForYouDetailItem(text: "Another placeholder line, slightly longer than the first one.", symbol: "drop"),
            ForYouDetailItem(text: "One more placeholder line.", symbol: "sun.max")
        ]
        case .third: [
            ForYouDetailItem(text: "Placeholder text for the third card.", symbol: "bolt"),
            ForYouDetailItem(text: "A short placeholder line.", symbol: "clock"),
            ForYouDetailItem(text: "A final placeholder line to fill the list.", symbol: "flag")
        ]
        case .fourth: [
            ForYouDetailItem(text: "Placeholder text for the fourth card.", symbol: "moon"),
            ForYouDetailItem(text: "A middle placeholder line.", symbol: "cloud"),
            ForYouDetailItem(text: "A last placeholder line to round things off.", symbol: "sparkle")
        ]
        }
    }
}
