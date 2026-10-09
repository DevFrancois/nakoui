import SwiftUI

/// One running stat, such as moves or pairs found, on a glass capsule. A
/// tint marks news, such as going over par, along with a change of symbol.
struct PawPairsStatChip: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color?

    var body: some View {
        Label {
            Text(title)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? QuizKind.pawPairs.tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline)
        .bold()
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(tint?.opacity(0.25)), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        PawPairsStatChip(title: "5 of 14 moves", systemImage: "flag.fill", tint: nil)
        PawPairsStatChip(title: "6 of 6 pairs", systemImage: "checkmark.seal.fill", tint: .green)
    }
    .padding()
    .background(.indigo.gradient)
}
