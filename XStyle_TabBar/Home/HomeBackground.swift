import SwiftUI

/// The shared base beneath Home's moving pages. The original blended wash
/// remains available in Debug Settings without making `ContentView` observe
/// the pager or the background preference.
struct HomeBackground: View {
    let pager: PagerState

    #if DEBUG
    @AppStorage(HomeBackgroundStyle.storageKey) private var style = HomeBackgroundStyle.pageAttached
    #else
    private let style = HomeBackgroundStyle.pageAttached
    #endif

    var body: some View {
        Group {
            if style == .originalBlended {
                AmbientGradientBackground(palettes: palettes, progress: progress)
            } else {
                Color(.pageBackground)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: pager.hapticTick)
    }

    /// During a tap transition only the two endpoints' palettes blend, so a
    /// distant tab is reached without passing through the skipped tabs' colors.
    private var palettes: [AmbientGradientPalette] {
        guard let tapTransition = pager.tapTransition else { return AppTab.allCases.map(\.palette) }
        return [tapTransition.source.palette, tapTransition.destination.palette]
    }

    private var progress: CGFloat {
        guard let tapTransition = pager.tapTransition else { return pager.progress }
        let source = CGFloat(tapTransition.source.index)
        let destination = CGFloat(tapTransition.destination.index)
        return min(max((pager.progress - source) / (destination - source), 0), 1)
    }
}
