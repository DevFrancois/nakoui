import SwiftUI

/// One clue under the pane. Until its stage arrives it's frosted over,
/// already in place so nothing below shifts when it thaws.
struct WhosHidingClueRow: View {
    let number: Int
    let clue: LocalizedStringResource
    let isRevealed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isRevealed ? "\(number).circle.fill" : "snowflake")
                .font(.title3)
                .foregroundStyle(isRevealed ? QuizKind.whosHiding.tint : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(clue)
                .font(.callout)
                .redacted(reason: isRevealed ? [] : .placeholder)
                .blur(radius: isRevealed ? 0 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(minHeight: TopMenuMetrics.minimumTapSize)
        .glassEffect(glass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var glass: Glass {
        isRevealed ? .regular.tint(QuizKind.whosHiding.tint.opacity(0.12)) : .regular
    }

    private var accessibilityText: Text {
        if isRevealed {
            Text("Clue \(number): \(Text(clue))")
        } else {
            Text("Clue \(number), still frosted")
        }
    }
}

#Preview {
    VStack {
        WhosHidingClueRow(number: 1, clue: "My teeth never stop growing.", isRevealed: true)
        WhosHidingClueRow(number: 2, clue: "I thump a back foot to warn of danger.", isRevealed: false)
    }
    .padding()
    .background(.purple.gradient)
}
