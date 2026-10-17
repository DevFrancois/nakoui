import SwiftUI

/// A static wash carried by its page, including the pager's compressed
/// source-to-destination transform for distant chip taps.
struct HomePageBackground: View {
    let tab: AppTab

    #if DEBUG
    @AppStorage(HomeBackgroundStyle.storageKey) private var style = HomeBackgroundStyle.pageAttached
    #else
    private let style = HomeBackgroundStyle.pageAttached
    #endif

    var body: some View {
        Group {
            if style == .pageAttached {
                AmbientGradientBackground(palettes: [tab.palette], progress: 0)
            }
        }
        // Clip to each page's width, but extend the clipped surface behind
        // the top menu and tab bar so the wash has no vertical seam.
        .clipped()
        .ignoresSafeArea(.container, edges: .vertical)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
