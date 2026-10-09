import SwiftUI

/// A task's action button in the sheet, matching the reference design:
/// accent-colored text a step up from regular, on a pale capsule of the same
/// color. Dark mode gets a stronger fill, so it still reads as blue rather
/// than navy.
struct TaskActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.tint)
            .padding(.horizontal, TaskMetrics.actionButtonHorizontalPadding)
            .padding(.vertical, TaskMetrics.actionButtonVerticalPadding)
            .background(.tint.opacity(fillOpacity(isPressed: configuration.isPressed)), in: .capsule)
            // The capsule stays slim; the tap area still meets the minimum.
            .frame(minHeight: TopMenuMetrics.minimumTapSize)
            .contentShape(.rect)
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        let base = colorScheme == .dark ? TaskMetrics.actionFillOpacityDark : TaskMetrics.actionFillOpacityLight
        return isPressed ? base * 2 : base
    }
}
