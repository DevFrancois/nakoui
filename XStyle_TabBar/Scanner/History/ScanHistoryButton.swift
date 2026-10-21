import SwiftUI
import TipKit

/// Opens the scan history. The first time it shows, its tip sits inline
/// beside it, pointing at it; it marks each scan added since with a
/// short-lived "+1" at its bottom-right.
struct ScanHistoryButton: View {
    let history: ScanHistory
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The scan the "+1" marks; 0 until one is added while the button shows.
    @State private var badgeTick = 0
    @State private var isBadgeShown = false
    /// Follows the tip's eligibility, so it can fade in and out.
    @State private var isTipShown = false
    private let tip = ScanHistoryTip()

    /// How long the "+1" stays.
    static let badgeDuration: Duration = .seconds(1.5)

    var body: some View {
        // Inline rather than a popover: with the button at the screen's edge,
        // a popover's arrow lands in its rounded corner. Empty once the tip is
        // used, and under the sheet while that's up.
        HStack {
            button
            if isTipShown {
                TipView(tip, arrowEdge: .leading)
                    .transition(.opacity)
            }
        }
        // The pane drops its transactions' animations; this one is its own.
        // The pane itself eases into the row's new height.
        .animation(.easeOut(duration: 0.2), value: isTipShown)
        .task {
            for await shouldDisplay in tip.shouldDisplayUpdates {
                isTipShown = shouldDisplay
            }
        }
    }

    private var button: some View {
        Button {
            tip.invalidate(reason: .actionPerformed)
            action()
        } label: {
            Label("Scan History", systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(GlassCircleButtonStyle())
        .accessibilityValue(Text("^[\(history.entries.count) product](inflect: true)"))
        .overlay(alignment: .bottomTrailing) {
            if isBadgeShown {
                ScanHistoryBadge()
                    .alignmentGuide(.trailing) { $0[.trailing] - 6 }
                    .alignmentGuide(.bottom) { $0[.bottom] - 4 }
                    .transition(badgeTransition)
            }
        }
        // The pane above drops its transactions' animations; this one is its own.
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .snappy, value: isBadgeShown)
        // Not on appear: the scan that revealed the button isn't new to it.
        .onChange(of: history.recordCount) {
            badgeTick = history.recordCount
        }
        // A scan while the badge shows starts it over.
        .task(id: badgeTick) {
            guard badgeTick > 0 else { return }
            isBadgeShown = true
            try? await Task.sleep(for: Self.badgeDuration)
            guard !Task.isCancelled else { return }
            isBadgeShown = false
        }
    }

    private var badgeTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity)
    }
}

/// The "+1" a new scan adds to the history button.
private struct ScanHistoryBadge: View {
    var body: some View {
        Text(verbatim: "+1")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.tint, in: .capsule)
            .fixedSize()
            // The button's value already says how many products there are.
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    ScanHistoryButton(history: PreviewFixtures.makeHistory(seeded: true), action: {})
        .padding()
}
#endif
