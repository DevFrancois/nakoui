import SwiftUI

/// The code cut out of the frozen frame. It starts warped onto the code where
/// it was seen, then lifts off, flattening into `target`.
struct LiftedCodePatch: View {
    let frozen: FrozenScan
    let target: CGRect
    /// 0 = on the code in the frame, 1 = flat at the target.
    let lift: CGFloat

    var body: some View {
        // Laid out from the overlay's origin, so the view's local coordinates
        // are the overlay's and the quads need no offset.
        Image(decorative: frozen.patch, scale: 1)
            .resizable()
            .frame(width: target.width + 2 * frozen.patchPadding, height: target.height + 2 * frozen.patchPadding)
            .brightness(0.04)
            .contrast(1.12)
            .modifier(QuadWarpEffect(quad: frozen.quad.lifted(to: target, lift), padding: frozen.patchPadding))
            .shadow(color: .black.opacity(0.25 * Double(lift)), radius: 3 * lift)
    }
}
