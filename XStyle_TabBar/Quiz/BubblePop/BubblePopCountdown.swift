import SwiftUI

/// The seconds left in the round inside a ring that runs down, on glass that
/// warms to orange near the end. It reads the clock every frame, so it stops
/// exactly where the round does.
struct BubblePopCountdown: View {
    /// Nil until the round starts, which shows a full clock.
    let start: Date?
    let stoppedAt: Date?
    let tint: Color

    @ScaledMetric(relativeTo: .headline) private var size = 44.0

    var body: some View {
        TimelineView(.animation(paused: start == nil || stoppedAt != nil)) { context in
            let duration = BubblePopMetrics.roundDuration
            let elapsed = start.map { (stoppedAt ?? context.date).timeIntervalSince($0) } ?? 0
            let remaining = min(max(duration - elapsed, 0), duration)
            let seconds = Int(remaining.rounded(.up))
            let isHurrying = start != nil && remaining <= BubblePopMetrics.hurryThreshold

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: remaining / duration)
                    .stroke(isHurrying ? .orange : tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(seconds, format: .number)
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: seconds)
            }
            .frame(width: size, height: size)
            .padding(6)
            .glassEffect(.regular.tint(isHurrying ? .orange.opacity(0.25) : nil), in: .circle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("^[\(seconds) second](inflect: true) left"))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
