import SwiftUI
import UIKit

/// SwiftUI owns the single material and its deformation. UIKit keeps the
/// controls and release-only tracker, measured against an unscaled anchor.
@MainActor
@Observable
final class GlassTabBarPresentation {
    private(set) var scale = CGSize(width: 1, height: 1)
    @ObservationIgnored weak var coordinateView: UIView?
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
                 duration: animated ? GlassTabBarMetrics.releaseDuration : nil, damping: 0.45)
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
