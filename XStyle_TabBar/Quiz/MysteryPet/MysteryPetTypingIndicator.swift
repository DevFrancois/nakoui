import SwiftUI

/// Three paw prints taking turns while the mystery pet "types" its next clue.
/// With Reduce Motion on, they light up in turn without hopping.
struct MysteryPetTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PhaseAnimator([0, 1, 2]) { phase in
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { paw in
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(paw == phase ? HierarchicalShapeStyle.primary : .tertiary)
                        .offset(y: paw == phase && !reduceMotion ? -MysteryPetMetrics.typingHop : 0)
                }
            }
        } animation: { _ in
            .easeInOut(duration: 0.2)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Typing"))
    }
}

#Preview {
    MysteryPetTypingIndicator()
        .padding()
        .glassEffect(in: .capsule)
        .padding()
        .background(.brown.gradient)
}
