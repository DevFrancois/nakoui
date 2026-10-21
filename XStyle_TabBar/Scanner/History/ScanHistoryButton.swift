import SwiftUI
import TipKit

/// Opens the scan history. The first time it shows, its tip sits inline
/// beside it, pointing at it; it marks the scans added since with a
/// short-lived "+1" at its bottom-right, once it's in view again.
struct ScanHistoryButton: View {
    let history: ScanHistory
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the sheet is over the button, as when a scan opens its result.
    @Environment(\.paneFooterIsCovered) private var isCovered
    /// The scans the "+1" has marked; nil until the button first shows.
    @State private var markedRecordCount: Int?
    @State private var isBadgeShown = false
    private let tip = ScanHistoryTip()

    /// How long the "+1" stays.
    static let badgeDuration: Duration = .seconds(1.5)

    var body: some View {
        // Inline rather than a popover: with the button at the screen's edge,
        // a popover's arrow lands in its rounded corner. Empty once the tip is
        // used, and under the sheet while that's up.
        HStack {
            button
            if history.isTipEligible {
                TipView(tip, arrowEdge: .leading)
                    .transition(.opacity)
            }
        }
        // The pane drops its transactions' animations; this one is its own.
        // The pane itself eases into the row's new height.
        .animation(.easeOut(duration: 0.2), value: history.isTipEligible)
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
        // A scan opens its result over the button: the "+1" waits for the
        // button to show again. A scan while it shows starts it over.
        .task(id: BadgeMoment(recordCount: history.recordCount, isCovered: isCovered)) {
            guard let marked = markedRecordCount else {
                // The scan that revealed the button isn't new to it.
                markedRecordCount = history.recordCount
                return
            }
            guard !isCovered else {
                isBadgeShown = false
                return
            }
            guard history.recordCount > marked else { return }
            isBadgeShown = true
            try? await Task.sleep(for: Self.badgeDuration)
            // Marked only once it has shown in full: the sheet rising over
            // the button cuts it short, and it plays again once it's gone.
            guard !Task.isCancelled else { return }
            markedRecordCount = history.recordCount
            isBadgeShown = false
        }
    }

    private var badgeTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity)
    }
}

/// When the "+1" may change: a scan, or the sheet leaving or covering the
/// button.
private struct BadgeMoment: Equatable {
    var recordCount: Int
    var isCovered: Bool
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
