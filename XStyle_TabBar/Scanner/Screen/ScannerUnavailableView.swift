import SwiftUI

/// Takes the camera's place when it can't run: access was refused, or there's
/// no camera to use.
struct ScannerUnavailableView: View {
    let state: ScannerState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: state == .denied ? "hand.raised" : "video.slash")
            }
        } description: {
            Text(description)
        } actions: {
            if state == .denied {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.glass)
            }
        }
    }

    private var title: LocalizedStringResource {
        state == .denied ? "Camera Access Needed" : "Camera Unavailable"
    }

    private var description: LocalizedStringResource {
        state == .denied
            ? "Allow camera access in Settings to scan product barcodes."
            : "The camera couldn't start, so barcodes can't be scanned right now."
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview("Denied") {
    ScannerUnavailableView(state: .denied)
}

#Preview("Unavailable") {
    ScannerUnavailableView(state: .unavailable)
}
