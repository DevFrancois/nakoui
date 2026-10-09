import SwiftUI

/// The pet placed in a slot, on glass that turns green or red once checked,
/// with its value and verdict. Until then, tapping it sends it back to the
/// pool.
struct LineUpSlotChip: View {
    let pet: LineUpPet
    /// The slot's position, counting from 1.
    let position: Int
    /// Nil until this slot's verdict is revealed.
    let mark: LineUpMark?
    let isLocked: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var minHeight = LineUpMetrics.chipHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The verdict beside the pet, or under it at accessibility sizes, so the
    /// name and value keep the chip's full width.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        Button(action: action) {
            layout {
                LineUpPetLabel(pet: pet, showsValue: mark != nil)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let mark {
                    LineUpMarkLabel(mark: mark, position: position)
                        .transition(reduceMotion ? AnyTransition.opacity : .scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(glass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .accessibilityLabel(
            Text("Position \(position), \(Text(pet.name))", comment: "VoiceOver label for a filled slot in Line 'Em Up: the slot's number, then the pet placed there.")
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isLocked ? Text(verbatim: "") : Text("Returns it to the pool."))
        .accessibilityRemoveTraits(isLocked ? .isButton : [])
        // Voice Control users can say the pet's name, not the whole label.
        .accessibilityInputLabels([Text(pet.name)])
    }

    private var glass: Glass {
        if let mark {
            mark.choiceState.glass
        } else {
            .regular.tint(pet.tint.opacity(0.15)).interactive(!isLocked)
        }
    }

    /// The value and verdict, once revealed.
    private var accessibilityValue: Text {
        if let mark {
            Text("\(Text(pet.value)), \(Text(mark.accessibilityDescription))")
        } else {
            Text(verbatim: "")
        }
    }
}
