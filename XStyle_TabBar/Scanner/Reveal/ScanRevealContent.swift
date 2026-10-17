import SwiftUI

/// The reveal at one instant, in full-screen coordinates over the camera. A
/// pure function of its inputs, so previews can pin any moment.
struct ScanRevealContent: View {
    let reveal: ScanReveal
    let frame: ScanRevealFrame

    var body: some View {
        GeometryReader { proxy in
            ScanRevealArtwork(reveal: reveal, frame: frame, viewSize: proxy.size)
        }
        // Flattened first, so the code doesn't show through the card as it fades.
        .compositingGroup()
        .opacity(frame.overlayOpacity)
    }
}

/// Geometry follows the live layout while the frozen pixels and animation
/// timeline keep their identity through a fold.
private struct ScanRevealArtwork: View {
    let reveal: ScanReveal
    let frame: ScanRevealFrame
    let viewSize: CGSize

    var body: some View {
        let viewfinder = Quad(ScannerMetrics.viewfinderRect(in: CGRect(origin: .zero, size: viewSize)))
        let quad = (reveal.frozen?.geometry ?? reveal.geometry).quad(in: viewSize)
        let layout = RevealLayout(viewSize: viewSize, codeQuad: quad)
        let outset = ScannerMetrics.bracketOutset
        let bracketTarget = quad
            .expanded(leading: outset, trailing: outset, top: outset, bottom: outset)
            .cornersAligned(to: viewfinder)

        ZStack(alignment: .topLeading) {
            if frame.isFrozen, let frozen = reveal.frozen {
                FrozenFrameBackdrop(frozen: frozen, blur: frame.blur)

                LiftedCodePatch(frozen: frozen, quad: quad, target: layout.liftTarget, lift: frame.lift)
                    .opacity(frame.patchOpacity)
            }

            QuadBrackets(quad: viewfinder.lerp(to: bracketTarget, frame.bracketProgress))
                .stroke(.white, style: StrokeStyle(lineWidth: ScannerMetrics.bracketLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(ScannerMetrics.bracketShadowOpacity), radius: 1.5)
                .opacity(frame.bracketOpacity)

            if reveal.frozen != nil, let bloom = reveal.bloom, let bloomTime = frame.bloomTime {
                BloomCanvas(plan: bloom, time: bloomTime, card: layout.card, cornerRadius: layout.cardCornerRadius)
                    .opacity(frame.cardOpacity)
            }

            if reveal.frozen != nil, let iconScale = frame.iconScale {
                ScanRevealIcon(size: layout.iconSize)
                    .scaleEffect(iconScale)
                    .opacity(frame.iconOpacity)
                    .position(x: layout.card.midX, y: layout.card.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Drag the slider to pin any moment of the reveal (seconds since detection).
#Preview("Scrub") {
    @Previewable @State var time = 1.2
    @Previewable @State var reveal: ScanReveal?
    @Previewable @Environment(\.displayScale) var displayScale

    ZStack {
        ScannerBackdropPlaceholder()
        GeometryReader { proxy in
            if let reveal {
                ScanRevealContent(
                    reveal: reveal,
                    frame: ScanRevealTimeline.frame(at: time, freezeTime: ScanRevealTimeline.freeze, closeTime: nil, reduceMotion: false)
                )
            }
            Color.clear
                .task {
                    reveal = await SimulatedScan(screenSize: proxy.size, displayScale: displayScale).reveal(of: .sampleEAN13)
                }
        }
    }
    .ignoresSafeArea()
    .overlay(alignment: .bottom) {
        VStack {
            Text(time, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
            Slider(value: $time, in: 0...ScanRevealTimeline.settleTime)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding()
    }
}
