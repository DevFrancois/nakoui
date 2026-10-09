import SwiftUI

/// The matches popped so far out of the round's total, on a glass capsule
/// that turns green once they're all found.
struct BubblePopFoundCounter: View {
    let found: Int
    let total: Int
    let tint: Color

    var body: some View {
        Label {
            Text("\(found)/\(total)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(found)))
        } icon: {
            Image(systemName: "bubbles.and.sparkles.fill")
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: found)
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(found == total ? .green.opacity(0.25) : nil), in: .capsule)
        .animation(.snappy, value: found)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Popped \(found) of \(total)"))
    }
}
