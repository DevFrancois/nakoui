import SwiftUI
import UIKit

/// SwiftUI owns the single material and its deformation. UIKit keeps the
/// controls and release-only tracker, measured against an unscaled anchor.
@MainActor
@Observable
final class GlassTabBarPresentation {
    private(set) var scale = CGSize(width: 1, height: 1)
    /// How the capsule and its highlight move; see `GlassTabBarMotion`.
    @ObservationIgnored var motion = GlassTabBarMotion.calm
    @ObservationIgnored weak var coordinateView: UIView?
    @ObservationIgnored weak var placementView: UIView?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isUpdatingView = false

    func updateView(_ update: () -> Void) {
        isUpdatingView = true
        defer { isUpdatingView = false }
        update()
    }

    func track(scale: CGSize, animated: Bool) {
        setScale(scale, duration: animated ? GlassTabBarMetrics.trackingDuration : nil, damping: 0.82)
    }

    func release(animated: Bool) {
        setScale(CGSize(width: 1, height: 1),
                 duration: animated ? motion.settleDuration : nil, damping: motion.releaseDamping)
    }

    func resetAfterLayout() {
        generation += 1
        let expectedGeneration = generation
        // Geometry/environment updates can arrive inside SwiftUI's update pass.
        // A newer touch must win over a deferred reset from an older placement.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.release(animated: false)
        }
    }

    func coordinateSpace(for view: UIView) -> UIView? {
        guard let coordinateView, let window = view.window,
              coordinateView.window === window,
              coordinateView.bounds.size == view.bounds.size else { return nil }
        return coordinateView
    }

    /// Where the toolbar has placed the bar: the center of its slot in the
    /// window. The bar's own grow and slide leave it alone, and so does the
    /// toolbar zooming the bar about that center as it shows it again; only
    /// a real move changes it.
    func placement(for view: UIView) -> CGPoint? {
        guard let placementView, let window = view.window, placementView.window === window else { return nil }
        let slot = placementView.bounds
        let center = placementView.convert(CGPoint(x: slot.midX, y: slot.midY), to: window)
        // Laid-out centers sit on whole or half pixels. Read to the half pixel,
        // a zoom's rounding error is never mistaken for a move.
        let step = 1 / (window.traitCollection.displayScale * 2)
        return CGPoint(x: (center.x / step).rounded() * step, y: (center.y / step).rounded() * step)
    }

    private func setScale(_ scale: CGSize, duration: TimeInterval?, damping: Double) {
        generation += 1
        if isUpdatingView {
            let expectedGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.setScale(scale, duration: duration, damping: damping)
            }
            return
        }
        if let duration {
            withAnimation(.interpolatingSpring(Spring(settlingDuration: duration, dampingRatio: damping))) {
                self.scale = scale
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.scale = scale }
        }
    }
}

struct GlassTabBarCoordinateSpace: UIViewRepresentable {
    let presentation: GlassTabBarPresentation

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        presentation.coordinateView = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

struct GlassTabBarPlacement: UIViewRepresentable {
    let presentation: GlassTabBarPresentation

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        presentation.placementView = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
