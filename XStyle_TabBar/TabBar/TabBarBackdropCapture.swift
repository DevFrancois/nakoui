import UIKit

/// Supplies the custom rim with colors from the app's visible surroundings.
/// Capturing the window also includes content beside a system-hosted toolbar.
@MainActor
final class TabBarBackdropCapture {
    struct Frame {
        /// Upright image: its first row corresponds to the top of the crop.
        /// Upload with a top-left texture origin to preserve UIKit coordinates.
        let image: CGImage
        let capsuleRect: CGRect
        let cropSize: CGSize
    }

    private var renderer: UIGraphicsImageRenderer?
    private var rendererSize: CGSize = .zero
    private var rendererScale: CGFloat = 0

    func capture(around view: UIView, reach: CGFloat = 96) -> Frame? {
        guard let window = view.window, reach.isFinite,
              !view.bounds.isEmpty else { return nil }

        let capsuleInWindow = view.convert(view.bounds, to: window)
        guard capsuleInWindow.width.isFinite, capsuleInWindow.height.isFinite,
              capsuleInWindow.minX.isFinite, capsuleInWindow.minY.isFinite,
              !capsuleInWindow.isEmpty else { return nil }

        let padding = max(0, reach) + 8
        let crop = capsuleInWindow
            .insetBy(dx: -padding, dy: -padding)
            .intersection(window.bounds)
        guard !crop.isNull, !crop.isEmpty,
              crop.width.isFinite, crop.height.isFinite else { return nil }

        let scale = min(1, 384 / max(crop.width, crop.height))
        if renderer == nil || rendererSize != crop.size || rendererScale != scale {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            format.preferredRange = .standard
            renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
            rendererSize = crop.size
            rendererScale = scale
        }
        guard let renderer else { return nil }

        let capsuleInCrop = capsuleInWindow.offsetBy(dx: -crop.minX, dy: -crop.minY)
        let snapshot = renderer.image { output in
            let context = output.cgContext
            context.clear(CGRect(origin: .zero, size: crop.size))
            context.saveGState()
            context.translateBy(x: -crop.minX, y: -crop.minY)

            // The context clips the full-window draw to the small crop. Keep
            // already displayed pixels without forcing a screen transaction.
            // A false result can mean an unsupported Metal/video layer was
            // omitted, including our own rim. Keep the usable partial image;
            // transparent pixels are rejected by the shader's weighted taps.
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            context.restoreGState()

            // Exclude the whole menu, its controls, and a guard band for
            // filtering/shadows. Never feed its previous lighting back into
            // the shader, and never hide or detach a live view for a capture.
            context.clear(capsuleInCrop.insetBy(dx: -6, dy: -6))
        }
        guard let image = snapshot.cgImage else { return nil }
        return Frame(image: image, capsuleRect: capsuleInCrop, cropSize: crop.size)
    }
}
