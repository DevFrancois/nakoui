import SwiftUI

/// Stands in for the camera feed in previews and the Simulator: a dim scene
/// with a product barcode label lined up in the viewfinder.
struct ScannerBackdropPlaceholder: View {
    /// A real EAN-13, so the simulated camera has something to decode.
    private static let modules = EAN13Modules.modules(for: ScannedCode.sampleEAN13.value) ?? []
    private static let labelTilt = Angle.degrees(-3)

    /// The label's corners in `bounds`, the full screen. The simulated scan
    /// "finds" the code here.
    static func labelQuad(in bounds: CGRect) -> Quad {
        let label = labelRect(in: bounds)
        let center = CGPoint(x: label.midX, y: label.midY)
        let angle = labelTilt.radians
        return Quad(label).map { p in
            let dx = p.x - center.x, dy = p.y - center.y
            return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
        }
    }

    private static func labelRect(in bounds: CGRect) -> CGRect {
        let window = ScannerMetrics.viewfinderRect(in: bounds)
        let size = CGSize(width: window.width * 0.7, height: window.height * 0.62)
        return CGRect(x: window.midX - size.width / 2, y: window.midY - size.height / 2, width: size.width, height: size.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let label = Self.labelRect(in: CGRect(origin: .zero, size: proxy.size))

            VStack(spacing: 4) {
                Canvas(renderer: drawBars)

                Text(ScannedCode.sampleEAN13.value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.black)
            }
            .padding()
            .frame(width: label.width, height: label.height)
            .background(.white, in: .rect(cornerRadius: 8))
            .rotationEffect(Self.labelTilt)
            .position(x: label.midX, y: label.midY)
        }
        .background {
            LinearGradient(colors: [Color(white: 0.3), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize) {
        let moduleWidth = size.width / Double(max(Self.modules.count, 1))
        var bars = Path()
        var runStart: Int?
        // One rect per run of bar modules, so wide bars have no seams.
        for (index, isBar) in (Self.modules + [false]).enumerated() {
            if isBar, runStart == nil {
                runStart = index
            } else if !isBar, let start = runStart {
                bars.addRect(CGRect(x: Double(start) * moduleWidth, y: 0, width: Double(index - start) * moduleWidth, height: size.height))
                runStart = nil
            }
        }
        context.fill(bars, with: .color(.black))
    }
}

#Preview {
    ScannerBackdropPlaceholder()
        .ignoresSafeArea()
}
