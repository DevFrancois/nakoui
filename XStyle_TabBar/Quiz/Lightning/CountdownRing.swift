import SwiftUI

/// The time left on a question, as a ring that runs down inside a glass
/// circle. It reads the clock each frame, so it can stop exactly where an
/// answer lands.
struct CountdownRing: View {
    let start: Date
    let duration: TimeInterval
    /// When set, the ring holds the time left at that moment.
    let stoppedAt: Date?
    let tint: Color

    @ScaledMetric(relativeTo: .title) private var size = 44.0

    var body: some View {
        TimelineView(.animation(paused: stoppedAt != nil)) { context in
            let now = stoppedAt ?? context.date
            let remaining = max(0, 1 - now.timeIntervalSince(start) / duration)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 5)

                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "bolt.fill")
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .padding(10)
        .glassEffect(in: .circle)
        .accessibilityHidden(true)
    }
}
