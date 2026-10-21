import SwiftUI

/// The live camera feed, drawn under the scanner's pane and out of its
/// collapse effects, which flatten what they draw: a camera layer can't be.
/// Black until the camera starts.
struct ScannerCameraFeed: View {
    let model: ScannerModel
    /// Owned above the pane, which the layout rebuilds, so the feed keeps its
    /// one preview layer.
    let previewHost: CameraPreviewHost
    #if DEBUG
    @Environment(\.paneIsCollapsing) private var paneIsCollapsing
    #endif

    var body: some View {
        ZStack {
            Color.black

            if let session = model.session, let device = model.cameraDevice {
                CameraPreview(host: previewHost, session: session, device: device,
                              onRotationChange: model.updatePreviewRotation)
            }
        }
        #if DEBUG
        .onChange(of: paneIsCollapsing) {
            if !paneIsCollapsing {
                previewHost.logState("back from the island")
            }
        }
        #endif
    }
}
