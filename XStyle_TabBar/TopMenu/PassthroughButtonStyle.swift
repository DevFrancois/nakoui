import SwiftUI

/// Draws the label unchanged. Chips get their press feedback from interactive
/// glass, so the dimming of `.plain` would only fight it.
struct PassthroughButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
