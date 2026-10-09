import SwiftUI

/// The reveal at one instant, in full-screen coordinates over the camera. A
/// pure function of its inputs, so previews can pin any moment.
struct ScanRevealContent: View {
    let reveal: ScanReveal
    let frame: ScanRevealFrame

    var body: some View {
        ZStack(alignment: .topLeading) {
            if frame.isFrozen, let frozen = reveal.frozen {
                FrozenFrameBackdrop(frozen: frozen, blur: frame.blur)

                LiftedCodePatch(frozen: frozen, target: frozen.layout.liftTarget, lift: frame.lift)
                    .opacity(frame.patchOpacity)
            }

            QuadBrackets(quad: reveal.viewfinder.lerp(to: bracketTarget, frame.bracketProgress))
                .stroke(.white, style: StrokeStyle(lineWidth: ScannerMetrics.bracketLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(ScannerMetrics.bracketShadowOpacity), radius: 1.5)
                .opacity(frame.bracketOpacity)

            if let frozen = reveal.frozen, let bloom = reveal.bloom, let bloomTime = frame.bloomTime {
                BloomCanvas(plan: bloom, time: bloomTime, card: frozen.layout.card, cornerRadius: frozen.layout.cardCornerRadius)
                    .opacity(frame.cardOpacity)
            }

            if let frozen = reveal.frozen, let iconScale = frame.iconScale {
                ScanRevealIcon(size: frozen.layout.iconSize)
                    .scaleEffect(iconScale)
                    .opacity(frame.iconOpacity)
                    .position(x: frozen.layout.card.midX, y: frozen.layout.card.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Flattened first, so the code doesn't show through the card as it fades.
        .compositingGroup()
        .opacity(frame.overlayOpacity)
    }

    /// The code the brackets close in on, with a little room around it.
    private var bracketTarget: Quad {
        let outset = ScannerMetrics.bracketOutset
        return (reveal.frozen?.quad ?? reveal.liveQuad)
            .expanded(leading: outset, trailing: outset, top: outset, bottom: outset)
            .cornersAligned(to: reveal.viewfinder)
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
