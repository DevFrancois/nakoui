import Foundation

/// Where a quick switch item leads, within its tab.
enum TabQuickSwitchDestination: Hashable {
    case homePage(AppTab)
    case pet(PetProfile.ID)
    case scan
    case scanHistory
    case searchScope(SearchScope)
}

/// One entry of a held tab's menu: a page, pet, view or scope to switch to.
struct TabQuickSwitchItem: Identifiable, Equatable {
    let tab: RootTab
    let destination: TabQuickSwitchDestination
    /// Resolved for the current locale, like the tab titles.
    let title: String
    let symbol: String
    /// What the tab shows now, or would on switching to it.
    var isCurrent = false

    var id: TabQuickSwitchDestination { destination }
}
