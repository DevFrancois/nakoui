import SwiftUI

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    let scanner: ScannerModel
    @ViewBuilder let home: Home

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: RootTab.home) {
                home
            } label: {
                Label(RootTab.home.title, systemImage: RootTab.home.symbol)
            }

            Tab(value: RootTab.scanner) {
                ScannerView(model: scanner, isActive: selection == .scanner)
            } label: {
                Label(RootTab.scanner.title, systemImage: RootTab.scanner.symbol)
            }

            ForEach(RootTab.placeholderTabs, id: \.self) { tab in
                Tab(value: tab) {
                    RootTabPlaceholder(tab: tab)
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }

            Tab(value: RootTab.search, role: .search) {
                RootTabPlaceholder(tab: .search)
            } label: {
                Label(RootTab.search.title, systemImage: RootTab.search.symbol)
            }
        }
    }
}
