import Testing
import Foundation
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchCatalogTests {
    private func context(isEnabled: Bool = true, isHistoryAvailable: Bool = false,
                         petID: PetProfile.ID = "miso") -> TabQuickSwitchCatalog.Context {
        TabQuickSwitchCatalog.Context(isEnabled: isEnabled, homePage: .likes, isHistoryAvailable: isHistoryAvailable,
                                      petID: petID, searchScope: .quizzes)
    }

    @Test("Home offers its pages in pager order, the shown page current")
    func homeOffersPages() {
        let items = TabQuickSwitchCatalog.items(for: .home, in: context())
        #expect(items.map(\.destination) == AppTab.allCases.map { .homePage($0) })
        #expect(items.map(\.title) == AppTab.allCases.map(\.title))
        #expect(items.filter(\.isCurrent).map(\.destination) == [.homePage(.likes)])
        #expect(items.allSatisfy { $0.tab == .home })
    }

    @Test("Scan has no menu until its history button shows, then Scan and History")
    func scanOffersHistoryOnceRevealed() {
        var isHistoryAvailable = false
        let menu = TabQuickSwitchMenu(items: { tab in
            TabQuickSwitchCatalog.items(for: tab, in: context(isHistoryAvailable: isHistoryAvailable))
        })
        #expect(TabQuickSwitchCatalog.items(for: .scanner, in: context()).map(\.destination) == [.scan])
        #expect(menu.items(for: .scanner, selectedTab: .scanner) == nil)
        isHistoryAvailable = true
        let items = menu.items(for: .scanner, selectedTab: .scanner)
        #expect(items?.map(\.destination) == [.scan, .scanHistory])
        // The camera is what the tab shows; the history only a sheet over it.
        #expect(items?.map(\.isCurrent) == [true, false])
        #expect(menu.items(for: .scanner, selectedTab: .home)?.map(\.isCurrent) == [false, false])
    }

    @Test("Profile offers the pets and Search its scopes, each with the stored one current")
    func profileAndSearchMarkStoredChoice() {
        let pets = TabQuickSwitchCatalog.items(for: .profile, in: context())
        #expect(pets.map(\.destination) == PetProfile.samples.map { .pet($0.id) })
        #expect(pets.filter(\.isCurrent).map(\.destination) == [.pet("miso")])
        let unknown = TabQuickSwitchCatalog.items(for: .profile, in: context(petID: "gone"))
        #expect(unknown.filter(\.isCurrent).map(\.destination) == [.pet(PetProfile.defaultID)])

        let scopes = TabQuickSwitchCatalog.items(for: .search, in: context())
        #expect(scopes.map(\.destination) == SearchScope.allCases.map { .searchScope($0) })
        #expect(scopes.filter(\.isCurrent).map(\.destination) == [.searchScope(.quizzes)])
    }

    @Test("Turned off, no tab offers anything, so every hold previews tabs as before")
    func offersNothingWhenOff() {
        for tab in RootTab.allCases {
            #expect(TabQuickSwitchCatalog.items(for: tab, in: context(isEnabled: false, isHistoryAvailable: true)).isEmpty)
        }
    }

    @Test("The context reads the setting, pet and scope from storage, with their defaults when unset")
    func readsStoredContext() throws {
        let suite = "TabQuickSwitchCatalogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pager = PagerState()
        let history = ScanHistory(defaults: defaults)

        var stored = TabQuickSwitchCatalog.context(pager: pager, history: history, defaults: defaults)
        #expect(stored.isEnabled == TabQuickSwitchSettings.defaultEnabled)
        #expect(stored.homePage == pager.selectedTab)
        #expect(stored.isHistoryAvailable == history.isButtonRevealed)
        #expect(stored.petID == PetProfile.defaultID)
        #expect(stored.searchScope == SearchScope.defaultScope)

        defaults.set(false, forKey: TabQuickSwitchSettings.enabledKey)
        defaults.set("pepper", forKey: PetProfile.storageKey)
        defaults.set(SearchScope.articles.rawValue, forKey: SearchScope.storageKey)
        stored = TabQuickSwitchCatalog.context(pager: pager, history: history, defaults: defaults)
        #expect(!stored.isEnabled)
        #expect(stored.petID == "pepper")
        #expect(stored.searchScope == .articles)
    }
}
