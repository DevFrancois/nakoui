import SwiftUI

/// The big reveal, on glass tinted with the breed's color: its emblem, who
/// you are, why, and a real fact about the breed.
struct PetMatchHeroCard: View {
    let breed: PetMatchBreed

    @ScaledMetric(relativeTo: .largeTitle) private var discSize = 104.0
    @State private var hasAppeared = false
    @AccessibilityFocusState private var isHeadlineFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: breed.symbol)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: hasAppeared)
                .frame(width: discSize, height: discSize)
                .background(breed.tint.gradient, in: .circle)
                .accessibilityHidden(true)

            // Only the heart takes the breed's color: orange or teal text
            // would be hard to read on light glass.
            Label {
                Text("It's a match!")
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(breed.tint)
            }
            .font(.headline)

            Text("You're a \(Text(breed.name))!")
                .font(.largeTitle)
                .bold()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadlineFocused)

            Text(breed.summary)

            Text("\(Image(systemName: "lightbulb.fill")) \(Text(breed.fact))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Breed fact: \(Text(breed.fact))"))
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(
            .regular.tint(breed.tint.opacity(0.18)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .onAppear(perform: celebrate)
    }

    /// Takes VoiceOver straight to the match, since the button that led
    /// here has gone, and bounces the emblem once as the card lands.
    private func celebrate() {
        isHeadlineFocused = true
        guard !reduceMotion else { return }
        hasAppeared = true
    }
}

#Preview {
    ScrollView {
        PetMatchHeroCard(breed: .goldenRetriever)
            .padding()
    }
    .background(.pink.gradient)
}
