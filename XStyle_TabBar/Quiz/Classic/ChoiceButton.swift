import SwiftUI

/// One multiple-choice answer as a full-width glass row.
struct ChoiceButton: View {
    let title: LocalizedStringResource
    let state: ChoiceState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(state == .dimmed ? .secondary : .primary)

                Spacer(minLength: 0)

                if let symbol = state.symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(state.symbolTint)
                        .accessibilityHidden(true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: TopMenuMetrics.minimumTapSize)
            .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(state.glass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .accessibilityValue(Text(state.accessibilityValue))
    }
}
