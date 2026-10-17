import SwiftUI

struct SidebarRouteView: View {
    let route: SidebarRoute

    var body: some View {
        Group {
            if let historyStyle = route.historyStyle {
                HistoryLab(style: historyStyle)
            } else {
                Text("Hello World")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .accessibilityIdentifier("destination.\(route.rawValue)")
    }
}
