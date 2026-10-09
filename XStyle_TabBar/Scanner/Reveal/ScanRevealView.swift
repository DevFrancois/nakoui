import SwiftUI

/// Plays the found-code animation from the display clock, then rests. Drawn
/// over the camera, ignoring the safe area like the preview.
struct ScanRevealView: View {
    let reveal: ScanReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    var body: some View {
        // Per-frame updates stop once nothing moves, until the next phase.
        TimelineView(.animation(paused: isSettled)) { context in
            ScanRevealContent(reveal: reveal, frame: reveal.frame(at: context.date, reduceMotion: reduceMotion))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: [reveal.freezeDate, reveal.closeDate]) {
            await settle()
        }
    }

    /// Resumes the clock for the current phase and pauses it when it's over.
    private func settle() async {
        isSettled = false
        let end: Date
        if let closeDate = reveal.closeDate {
            end = closeDate.addingTimeInterval(ScanRevealTimeline.closeDuration)
        } else if let freezeTime = reveal.freezeTime {
            end = reveal.startDate.addingTimeInterval(freezeTime - ScanRevealTimeline.freeze + ScanRevealTimeline.settleTime)
        } else {
            // Still live: rest once the brackets have landed. New positions
            // still redraw, and a freeze or close starts the clock again.
            end = reveal.startDate.addingTimeInterval(ScanRevealTimeline.bracketFlightDuration)
        }
        try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
        if !Task.isCancelled {
            isSettled = true
        }
    }
}
