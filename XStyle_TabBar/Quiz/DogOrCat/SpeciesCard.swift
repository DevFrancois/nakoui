import SwiftUI

/// The fact to sort, on a glass card that follows a drag: it tilts and takes
/// on the color of the animal it's heading toward. Once answered, it shows
/// which animal the fact belongs to.
struct SpeciesCard: View {
    let statement: SpeciesStatement
    let dragOffset: Double
    /// The right animal, once the fact has been sorted.
    let answer: PetSpecies?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: QuizMetrics.sectionSpacing) {
            Text(statement.text)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            if let answer {
                Label(answer.title, systemImage: answer.symbol)
                    .font(.headline)
                    .foregroundStyle(answer.tint)
            } else {
                HStack {
                    Label("Dog", systemImage: "arrow.left")
                    Spacer()
                    Label {
                        Text("Cat")
                    } icon: {
                        Image(systemName: "arrow.right")
                    }
                    .labelStyle(TrailingIconLabelStyle())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
        .glassEffect(.regular.tint(leaningTint), in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .offset(x: reduceMotion ? 0 : dragOffset)
        .rotationEffect(.degrees(reduceMotion ? 0 : dragOffset / QuizMetrics.swipeTiltDivisor))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Choose Dog or Cat with the buttons below."))
    }

    /// The color of the animal the card is dragged toward, or of the answer.
    private var leaningTint: Color? {
        if let answer {
            return answer.tint.opacity(0.25)
        }
        guard dragOffset != 0 else { return nil }
        let species: PetSpecies = dragOffset < 0 ? .dog : .cat
        let strength = min(abs(dragOffset) / QuizMetrics.swipeThreshold, 1)
        return species.tint.opacity(0.35 * strength)
    }
}
