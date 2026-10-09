import SwiftUI

/// Presses a hub card in slightly, in place of interactive glass.
struct QuizCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
