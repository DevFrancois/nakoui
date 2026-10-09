import SwiftUI

/// Highlights a task card's tappable area while it's pressed, like a list
/// row, rather than scaling or dimming the whole card.
struct TaskCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear))
    }
}
