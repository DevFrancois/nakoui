import SwiftUI

/// The Home tab's background, washing between the pages' colors as the
/// pager moves, with a tick as it passes each page. It reads the pager
/// itself, so a swipe redraws the background and not `ContentView`.
struct HomeBackground: View {
    let pager: PagerState

    var body: some View {
        AmbientGradientBackground(palettes: palettes, progress: progress)
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
