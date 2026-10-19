import SwiftUI

/// The pane under the camera: the aiming hint, then the code a scan found,
/// with Copy, Scan Again, and a close button in the corner. The details
/// scroll below the close row, so dragging along the pane's top edge still
/// moves the pane.
struct ScannerResultPane: View {
    let model: ScannerModel

    var body: some View {
        ZStack {
            if let code = model.scannedCode {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Close", systemImage: "xmark", action: model.scanAgain)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                    }
                    .padding([.top, .horizontal])

                    ScrollView {
                    VStack(spacing: 20) {
                        ScannedCodeDetails(code: code)

                        GlassEffectContainer {
                            HStack(spacing: 12) {
                                Button("Copy", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = code.value
                                }
                                Button("Scan Again", systemImage: "barcode.viewfinder", action: model.scanAgain)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .transition(.blurReplace)
            } else {
                VStack(spacing: 16) {
                    Label("Point at a product barcode", systemImage: "barcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    #if targetEnvironment(simulator)
                    ScannerSimulateButton(action: model.simulateScan)
                        .disabled(model.reveal != nil)
                    #endif
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.reveal == nil ? 1 : 0)
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: model.scannedCode)
        .animation(.easeOut(duration: 0.15), value: model.reveal == nil)
    }
}

#Preview("Aiming") {
    ScannerResultPane(model: ScannerModel(state: .scanning))
}

#Preview("Found") {
    ScannerResultPane(model: ScannerModel(state: .scanning, scannedCode: .sampleEAN13))
}
