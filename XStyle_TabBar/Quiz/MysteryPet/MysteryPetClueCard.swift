import SwiftUI

/// One clue in the mystery pet's own words, as a glass speech bubble whose
/// tail points back at the pet. It starts as a small typing bubble that
/// grows into the clue; the newest clue is tinted, and extra clues shown
/// only after the answer step back.
struct MysteryPetClueCard: View {
    let number: Int
    let text: LocalizedStringResource
    let state: MysteryPetClueState
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if state == .typing {
                MysteryPetTypingIndicator()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            } else {
                // The number sits above the clue at accessibility sizes, so
                // long words get the bubble's full width.
                numberAndClueLayout {
                    // Filled for clues the player asked for, outlined for extras.
                    Image(systemName: state == .extra ? "\(number).circle" : "\(number).circle.fill")
                        .foregroundStyle(state == .extra ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                        .imageScale(.large)

                    Text(text)
                        .foregroundStyle(state == .extra ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.body)
                .padding()
            }
        }
        .glassEffect(glass, in: bubble)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Clue \(number)"))
        // Doesn't give the clue away before it has landed.
        .accessibilityValue(state == .typing ? Text("Typing") : Text(text))
    }

    private var numberAndClueLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        } else {
            AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        }
    }

    private var glass: Glass {
        state == .latest ? .regular.tint(tint.opacity(0.2)) : .regular
    }

    private var bubble: UnevenRoundedRectangle {
        .rect(
            topLeadingRadius: MysteryPetMetrics.bubbleTailRadius,
            bottomLeadingRadius: QuizMetrics.answerCornerRadius,
            bottomTrailingRadius: QuizMetrics.answerCornerRadius,
            topTrailingRadius: QuizMetrics.answerCornerRadius
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        MysteryPetClueCard(number: 1, text: "I was bred in Germany to follow badgers right into their burrows.", state: .earlier, tint: .brown)
        MysteryPetClueCard(number: 2, text: "I come in three coats: smooth, wirehaired and longhaired.", state: .latest, tint: .brown)
        MysteryPetClueCard(number: 3, text: "Typing", state: .typing, tint: .brown)
        MysteryPetClueCard(number: 4, text: "Lots of people call me a wiener dog or a sausage dog.", state: .extra, tint: .brown)
    }
    .padding()
    .background(.orange.gradient)
}
