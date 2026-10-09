import SwiftUI

/// One answer as a big glass mood tile: a symbol in the tile's accent over a
/// short title. The pick glows pink, bounces its symbol and earns a
/// checkmark, so it never shows by color alone.
struct PetMatchMoodTile: View {
    let answer: PetMatchAnswer
    let tint: Color
    let state: PetMatchTileState
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var minHeight = 128.0
    @State private var pickBounces = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPicked: Bool {
        state == .picked
    }

    /// Keeps tiles one size across questions. At accessibility text sizes the
    /// tiles stack in one column and size to their content, since the scaled
    /// minimum would make each one mostly empty space, several hundred
    /// points tall.
    private var tileMinHeight: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : CGFloat(minHeight)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: answer.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(tint)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: pickBounces)
                    .accessibilityHidden(true)

                Text(answer.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(state == .passed ? .secondary : .primary)
            }
            .padding()
            // Fills its grid cell, so tiles sharing a row match in height.
            .frame(maxWidth: .infinity, minHeight: tileMinHeight, maxHeight: .infinity)
            // Inside the label, so the glass draws it crisply on top.
            .overlay(alignment: .topTrailing) {
                if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(QuizKind.petMatch.tint)
                        .padding(10)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(state.glass(tint: tint), in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .scaleEffect(isPicked && !reduceMotion ? 1.04 : 1)
        .onChange(of: state) { _, newState in
            bounceIfPicked(newState)
        }
        // VoiceOver says "Selected" for the pick; the other tiles need no value.
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func bounceIfPicked(_ newState: PetMatchTileState) {
        guard newState == .picked, !reduceMotion else { return }
        pickBounces += 1
    }
}

#Preview {
    HStack {
        PetMatchMoodTile(
            answer: PetMatchRounds.all[0].answers[0],
            tint: PetMatchMetrics.tileTint(at: 0),
            state: .picked
        ) {}

        PetMatchMoodTile(
            answer: PetMatchRounds.all[0].answers[1],
            tint: PetMatchMetrics.tileTint(at: 1),
            state: .passed
        ) {}
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding()
    .background(.pink.gradient)
}
