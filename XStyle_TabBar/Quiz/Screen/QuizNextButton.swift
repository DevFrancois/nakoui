import SwiftUI

/// Moves to the next question, or to the results after the last one.
struct QuizNextButton: View {
    let tint: Color
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLast {
                    Label("See results", systemImage: "flag.checkered")
                } else {
                    Label("Next", systemImage: "arrow.forward")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .controlSize(.large)
    }
}
