import SwiftUI

/// The frozen frame, aspect-filled and centred exactly like the live preview,
/// crossfading to its blurred, frosted copy when the freeze made one.
struct FrozenFrameBackdrop: View {
    let frozen: FrozenScan
    /// 0 = sharp, 1 = fully blurred.
    let blur: Double

    var body: some View {
        // Centred in a clear full-screen frame: a bare fill in a top-leading
        // stack would pin the overflow to the corner instead.
        Color.clear
            .overlay {
                ZStack {
                    Image(decorative: frozen.sharp, scale: 1)
                        .resizable()
                        .scaledToFill()

                    if let blurred = frozen.blurred {
                        Image(decorative: blurred, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .opacity(blur)
                    }
                }
            }
            .clipped()
    }
}
