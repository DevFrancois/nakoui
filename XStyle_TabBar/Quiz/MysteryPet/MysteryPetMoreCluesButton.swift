import SwiftUI

/// Asks the mystery pet for its next clue, with the price on the button: a
/// paw off the points meter, or free once the meter is down to its last paw.
struct MysteryPetMoreCluesButton: View {
    let worthNow: Int
    /// What a right answer will be worth with the next clue showing.
    let worthAfter: Int
    let tint: Color
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cost: Int {
        worthNow - worthAfter
    }

    private var hint: LocalizedStringResource {
        if cost > 0 {
            "Lowers a right answer to ^[\(worthAfter) point](inflect: true)."
        } else {
            "Free: a right answer stays worth ^[\(worthAfter) point](inflect: true)."
        }
    }

    /// The price sits under the title at accessibility sizes, so neither
    /// has to break mid-word.
    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        } else {
            AnyLayout(HStackLayout(spacing: 8))
        }
    }

    /// A pill, or a rounded card once large text makes it tall enough for a
    /// pill's ends to cut into the text.
    private var shape: AnyShape {
        if dynamicTypeSize.isAccessibilitySize {
            AnyShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        } else {
            AnyShape(.capsule)
        }
    }

    var body: some View {
        Button(action: action) {
            layout {
                Label("Another clue", systemImage: "plus.bubble.fill")
                    .font(.headline)

                Spacer(minLength: 0)

                Group {
                    if cost > 0 {
                        Label {
                            Text(-cost, format: .number)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "pawprint.fill")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        // The last clue costs nothing: the meter never drops below one paw.
                        Label {
                            Text("Free")
                        } icon: {
                            Image(systemName: "gift.fill")
                                .foregroundStyle(tint)
                        }
                    }
                }
                .font(.subheadline)
                .bold()
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: MysteryPetMetrics.controlHeight, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(.regular.tint(tint.opacity(0.25)).interactive(), in: shape)
        .accessibilityHint(Text(hint))
    }
}

#Preview {
    VStack {
        MysteryPetMoreCluesButton(worthNow: 3, worthAfter: 2, tint: .brown) {}
        MysteryPetMoreCluesButton(worthNow: 1, worthAfter: 1, tint: .brown) {}
    }
    .padding()
    .background(.orange.gradient)
}
