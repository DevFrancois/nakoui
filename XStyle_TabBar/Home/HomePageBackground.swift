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
        // A wash must stop at its own page boundary, even while the
        // underlying gradient extends into the safe area.
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
