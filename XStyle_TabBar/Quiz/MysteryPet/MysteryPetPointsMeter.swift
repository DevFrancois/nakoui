import SwiftUI

/// What a right answer is worth right now: three paws on a glass capsule
/// that empty one by one as more clues come in. Lit paws are filled, spent
/// ones outlined, so the meter doesn't rely on color alone.
struct MysteryPetPointsMeter: View {
    let points: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<MysteryPetRounds.maxPoints, id: \.self) { paw in
                Image(systemName: paw < points ? "pawprint.fill" : "pawprint")
                    .foregroundStyle(paw < points ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: MysteryPetMetrics.controlHeight)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Worth ^[\(points) point](inflect: true)"))
    }
}

#Preview {
    VStack {
        MysteryPetPointsMeter(points: 3, tint: .brown)
        MysteryPetPointsMeter(points: 1, tint: .brown)
    }
    .padding()
    .background(.orange.gradient)
}
