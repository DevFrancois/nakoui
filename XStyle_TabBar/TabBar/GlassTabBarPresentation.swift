import SwiftUI
import UIKit

/// Shares the native glass controls' geometry with SwiftUI. UIKit keeps the
/// release-only tracker; the system owns the capsule's touch response.
@MainActor
@Observable
final class GlassTabBarPresentation {
    /// The Scan symbol's centre within the controls, as UIKit laid it out.
    private(set) var scanSymbol: UnitPoint?
    /// How the highlight and toolbar entrance move; see `GlassTabBarMotion`.
    @ObservationIgnored var motion = GlassTabBarMotion.calm
    @ObservationIgnored weak var coordinateView: UIView?
    @ObservationIgnored weak var placementView: UIView?

    func setScanSymbol(x: CGFloat, y: CGFloat) {
        let point = UnitPoint(x: x, y: y)
        if scanSymbol != point { scanSymbol = point }
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
