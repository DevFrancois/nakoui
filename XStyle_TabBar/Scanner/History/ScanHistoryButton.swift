import SwiftUI
import TipKit

/// Opens the scan history, from a corner. The first time it shows, its tip
/// sits inline below it, pointing up at it; it marks the scans added since
/// with a short-lived "+1" at its bottom-right.
struct ScanHistoryButton: View {
    let history: ScanHistory
    /// Whether the tip may show: not while a sheet is up, which it would sit
    /// over or beside. It shows again after, until it's used.
    var showsTip: Bool
    /// The button's distance from the top and leading edges of its corner.
    var cornerInset: CGFloat
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The scans the "+1" has marked; nil until the button first shows.
    @State private var markedRecordCount: Int?
    @State private var isBadgeShown = false
    /// Counts the taps, each played as a light tap.
    @State private var openCount = 0
    /// Kept by TipKit: false as the tip's own close folds it away, in that
    /// update, before `isTipEligible` follows. Starts true, as false would
    /// hold back a tip that may show.
    @State private var isTipPresented = true
    private let tip = ScanHistoryTip()

    /// How long the "+1" stays.
    static let badgeDuration: Duration = .seconds(1.5)

    var body: some View {
        // The button first, so the tip below never moves it. The tip spans
        // the corner's width at the standard margin, its arrow aimed at the
        // button, clear of its rounded corner. Empty once the tip is used.
        VStack(alignment: .leading) {
            button
                .tipAnchor(TipAnchor.button)
                .padding(.leading, cornerInset)
            if isTipShown {
                TipView(tip, isPresented: $isTipPresented, arrowEdge: .top, anchorID: TipAnchor.button)
                    .padding(.horizontal)
                    .transition(.opacity)
            }
        }
        .padding(.top, cornerInset)
        // The pane drops its transactions' animations, TipKit's included;
        // these are its own. The second fades the tip as its own close folds
        // it away.
        .animation(.easeOut(duration: 0.2), value: isTipShown)
        .animation(.easeOut(duration: 0.2), value: isTipPresented)
    }

    private nonisolated enum TipAnchor: Hashable, Sendable {
        case button
    }

    private var isTipShown: Bool {
        history.isTipEligible && showsTip
    }

    private var button: some View {
        Button {
            openCount += 1
            tip.invalidate(reason: .actionPerformed)
            action()
        } label: {
            Label("Scan History", systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(GlassCircleButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: openCount)
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
        // A scan happens only with the camera in view, the sheet at medium at
        // most, so the "+1" shows at once. A scan while it shows starts it
        // over.
        .task(id: history.recordCount) {
            guard let marked = markedRecordCount else {
                // The scan that revealed the button isn't new to it.
                markedRecordCount = history.recordCount
                return
            }
            guard history.recordCount > marked else { return }
            isBadgeShown = true
            try? await Task.sleep(for: Self.badgeDuration)
            // Marked only once it has shown in full: leaving the tab cuts it
            // short, and it plays again on return rather than sticking.
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
    ScanHistoryButton(history: PreviewFixtures.makeHistory(seeded: true), showsTip: true, cornerInset: 16, action: {})
}
#endif
