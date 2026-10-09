import SwiftUI

/// An icon-only button in the top menu's logo row, with a full-size tap area
/// and its title kept for VoiceOver.
struct TopMenuIconButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
            .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
            .contentShape(.rect)
        }
    }
}
