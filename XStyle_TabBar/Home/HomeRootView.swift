import SwiftUI

/// Keeps the pager, stationary chrome and page backgrounds together without
/// making the navigation stack observe their scrolling state.
struct HomeRootView<Leading: View>: View {
    let title: String
    let pager: PagerState
    let logoCollapse: LogoCollapse
    let taskList: ForYouTaskList
    let zoomNamespace: Namespace.ID
    let onSelect: (AppTab) -> Void
    let onUpdate: () -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        HomePager(
            pager: pager,
            logoCollapse: logoCollapse,
            taskList: taskList,
            zoomNamespace: zoomNamespace,
            onUpdate: onUpdate
        )
        .safeAreaBar(edge: .top, spacing: 0) {
            HomeTopMenu(
                title: title,
                pager: pager,
                logoCollapse: logoCollapse,
                onSelect: onSelect
            ) {
                leading
            }
        }
        .background {
            HomeBackground(pager: pager)
        }
    }
}
