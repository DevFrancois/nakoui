import SwiftUI

/// The wrong pops the player can still take, as paws on a glass capsule. A
/// paw empties with each wrong pop, and the glass warms to red.
struct BubblePopLives: View {
    let lives: Int
    let total: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: index < lives ? "pawprint.fill" : "pawprint")
                    .foregroundStyle(index < lives ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: index < lives)
            }
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(lives < total ? .red.opacity(0.2) : nil), in: .capsule)
        .animation(.snappy, value: lives)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Paws left: \(lives) of \(total)"))
    }
}
