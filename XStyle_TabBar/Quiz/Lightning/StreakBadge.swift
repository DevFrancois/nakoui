import SwiftUI

/// The run of right answers, warming to orange once a streak gets going.
struct StreakBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let streak: Int

    var body: some View {
        Label {
            Text(streak, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(streak)))
        } icon: {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 1 ? .orange : .secondary)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : streak)
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(streak > 1 ? .orange.opacity(0.25) : nil), in: .capsule)
        .animation(reduceMotion ? nil : .snappy, value: streak)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Streak: \(streak)"))
    }
}
