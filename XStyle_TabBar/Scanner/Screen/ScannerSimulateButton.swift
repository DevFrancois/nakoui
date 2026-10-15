import SwiftUI

#if targetEnvironment(simulator)
/// Simulator only: pretends the camera read a barcode, so both result styles
/// can be tried without an iPhone, including in live previews.
struct ScannerSimulateButton: View {
    let action: () -> Void

    var body: some View {
        Button("Simulate Scan", systemImage: "barcode.viewfinder", action: action)
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.bottom)
    }
}

#Preview {
    ScannerSimulateButton {}
}
#endif
