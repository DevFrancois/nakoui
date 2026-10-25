import Foundation

/// The items each tab's menu offers.
enum TabQuickSwitchCatalog {
    /// What the items depend on, read as a hold opens a menu.
    struct Context {
        var isEnabled = TabQuickSwitchSettings.defaultEnabled
        var homePage: AppTab
        /// Whether the Scan tab shows its history button yet.
        var isHistoryAvailable: Bool
        var petID: PetProfile.ID
        var searchScope: SearchScope
    }

    static func context(pager: PagerState, history: ScanHistory, defaults: UserDefaults = .standard) -> Context {
        Context(
            isEnabled: TabQuickSwitchSettings.isEnabled(in: defaults),
            homePage: pager.selectedTab,
            isHistoryAvailable: history.isButtonRevealed,
            petID: defaults.string(forKey: PetProfile.storageKey) ?? PetProfile.defaultID,
            searchScope: defaults.string(forKey: SearchScope.storageKey).flatMap(SearchScope.init(rawValue:))
                ?? SearchScope.defaultScope
        )
    }

    /// None while the menu is turned off. A tab with fewer than two items
    /// shows no menu; see `TabQuickSwitchMenu.items(for:)`.
    static func items(for tab: RootTab, in context: Context) -> [TabQuickSwitchItem] {
        guard context.isEnabled else { return [] }
        switch tab {
        case .home:
            return AppTab.allCases.map { page in
                TabQuickSwitchItem(tab: tab, destination: .homePage(page), title: page.title, symbol: page.symbol,
                                   isCurrent: page == context.homePage)
            }
        case .scanner:
            // History joins once the Scan tab shows its button.
            let scan = TabQuickSwitchItem(tab: tab, destination: .scan, title: String(localized: "Scan"),
                                          symbol: RootTab.scanner.symbol)
            let history = TabQuickSwitchItem(tab: tab, destination: .scanHistory, title: String(localized: "History"),
                                             symbol: "clock.arrow.circlepath")
            return context.isHistoryAvailable ? [scan, history] : [scan]
        case .profile:
            let currentID = PetProfile.pet(for: context.petID).id
            return PetProfile.samples.map { pet in
                TabQuickSwitchItem(tab: tab, destination: .pet(pet.id), title: pet.name, symbol: pet.symbol,
                                   isCurrent: pet.id == currentID)
            }
        case .search:
            return SearchScope.allCases.map { scope in
                TabQuickSwitchItem(tab: tab, destination: .searchScope(scope), title: String(localized: scope.title),
                                   symbol: scope.symbol, isCurrent: scope == context.searchScope)
            }
        }
    }
}
