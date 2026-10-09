import SwiftUI

/// A large glass answer with a symbol over its title, used for Dog/Cat and
/// True/False. Idle tiles carry a hint of their own color.
struct AnswerTile: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    let state: ChoiceState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(state == .dimmed ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            // Inside the label, so the glass draws it crisply on top rather
            // than blending it in, as it does with overlays on the glass itself.
            .overlay(alignment: .topTrailing) {
                if let symbol = state.symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(state.symbolTint)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(glass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .accessibilityValue(Text(state.accessibilityValue))
    }

    private var glass: Glass {
        state == .idle ? .regular.tint(tint.opacity(0.2)).interactive() : state.glass
    }
}

#Preview {
    HStack {
        AnswerTile(title: "Dog", systemImage: "dog.fill", tint: .orange, state: .idle) {}
        AnswerTile(title: "Cat", systemImage: "cat.fill", tint: .purple, state: .correct) {}
    }
    .padding()
    .background(.orange.gradient)
}
