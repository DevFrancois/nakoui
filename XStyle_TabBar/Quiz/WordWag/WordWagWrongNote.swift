import SwiftUI

/// Says a full guess isn't the breed, in words and a symbol as well as the
/// red tiles, and how to fix it.
struct WordWagWrongNote: View {
    var body: some View {
        Label {
            Text("Not quite! Tap a letter to send it back.")
        } icon: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
        .font(.subheadline)
        .bold()
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(.red.opacity(0.15)),
            in: .rect(cornerRadius: QuizMetrics.answerCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WordWagWrongNote()
        .padding()
        .background(.mint.gradient)
}
