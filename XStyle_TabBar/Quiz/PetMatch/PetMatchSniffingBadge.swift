import SwiftUI

/// Sniffs out the match before the reveal: the breed emblems shuffle like a
/// slot machine inside a glass circle, which then grows into the result.
/// With Reduce Motion on, a paw print holds still instead.
struct PetMatchSniffingBadge: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size = 120.0
    @State private var shuffleIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var breed: PetMatchBreed {
        PetMatchBreed.allCases[shuffleIndex % PetMatchBreed.allCases.count]
    }

    var body: some View {
        Image(systemName: reduceMotion ? "pawprint.fill" : breed.symbol)
            .font(.largeTitle)
            .imageScale(.large)
            .foregroundStyle(reduceMotion ? QuizKind.petMatch.tint : breed.tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(QuizKind.petMatch.tint.opacity(0.15)), in: .circle)
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                await shuffle()
            }
    }

    /// Steps through the emblems until the reveal removes the badge, and
    /// stops at once then rather than taking one more step.
    private func shuffle() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: PetMatchMetrics.shuffleInterval)
            } catch {
                return
            }
            withAnimation(.snappy) {
                shuffleIndex += 1
            }
        }
    }
}

#Preview {
    PetMatchSniffingBadge()
        .padding()
        .background(.pink.gradient)
}
