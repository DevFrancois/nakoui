import SwiftUI

/// What can be done with a found code, at the top of its report: copy its
/// digits, or close the result and scan again.
struct ScannedCodeActions: View {
    let code: ScannedCode
    let onScanAgain: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = code.value
                }
                Button("Scan Again", systemImage: "barcode.viewfinder", action: onScanAgain)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}

#Preview {
    ScannedCodeActions(code: .sampleEAN13) {}
}
