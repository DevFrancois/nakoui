import BarcodeDecoding
@preconcurrency import AVFoundation
import CoreImage

/// Decodes camera frames as they arrive. The actor runs on the very queue the
/// video output calls back on, so each frame is decoded synchronously inside
/// the callback: no hop per frame, and late frames are dropped by the output
/// instead of piling up. Only results cross to the main actor.
actor FrameAnalyzer {
    nonisolated let queue = DispatchSerialQueue(label: "dev.kavsoft.XStyle-TabBar.scanner.video", qos: .userInteractive)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private enum Mode {
        case scanning
        /// Following a confirmed code until the frame is frozen.
        case tracking(String)
        case paused
    }

    private let decoder = BarcodeDecoder()
    private var confirmer = ReadingConfirmer()
    private var mode = Mode.scanning
    private var screen: ScannerViewport?
    private var mapper: AspectFillMapper?
    private var region: ScanRegion?
    /// The newest frame the tracked code was read in, kept for the freeze.
    private var tracked: (reading: BarcodeReading, frame: CVPixelBuffer)?
    private var lastFrameTime = 0.0
    private var isWarmedUp = false
    private var continuation: AsyncStream<ScanEvent>.Continuation?

    /// A fresh stream of results for one scanning run. A stream ends for good
    /// once the task reading it is cancelled, so each run asks for its own.
    /// Unbounded: a dropped detection would leave the analyzer tracking a code
    /// nobody shows, and the events are tiny.
    func events() -> AsyncStream<ScanEvent> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self, bufferingPolicy: .unbounded)
        self.continuation = continuation
        return stream
    }

    func setViewport(_ viewport: ScannerViewport) {
        guard viewport.size.width > 0, viewport.size.height > 0,
              screen.map({ viewport.revision >= $0.revision }) ?? true else { return }
        screen = viewport
        mapper = nil
    }

    /// Scans again after a result, holding `text` back until it has left the frame.
    func resume(suppressing text: String?) {
        confirmer.reset(suppressing: text)
        tracked = nil
        mode = .scanning
    }

    /// Stops decoding and prepares the newest frame of the tracked code for the reveal.
    func freeze(viewport: ScannerViewport?) -> FrozenScan? {
        // The capture queue may still be forwarding the scene's newest
        // geometry. Freeze the retained raw frame in that same configuration.
        if let viewport { setViewport(viewport) }
        defer {
            tracked = nil
            mode = .paused
        }
        guard let tracked, let screen else { return nil }
        // A resize invalidates the mapper even if no newer camera frame
        // arrives before the freeze. The retained frame is sufficient.
        let mapper = currentMapper(for: tracked.frame, screen: screen)
        let bufferQuad = Self.outline(of: tracked.reading)
        return FrozenScanRenderer.render(
            CIImage(cvPixelBuffer: tracked.frame), rotation: screen.rotation, codeQuad: bufferQuad,
            viewQuad: bufferQuad.map(mapper.viewPoint), viewSize: screen.size, displayScale: screen.displayScale
        )
    }

    /// Called on `queue` for every frame, from inside the output's callback.
    func analyze(_ sampleBuffer: CMSampleBuffer) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyze(frame, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }

    #if targetEnvironment(simulator)
    /// Feeds `still` as if the camera kept seeing it, until the code it shows
    /// is frozen for the reveal or a few seconds pass. Runs the whole real
    /// pipeline (decoding, confirmation, tracking, freeze) without a camera.
    func playSimulatedCamera(_ still: SimulatedStill) async {
        guard let frame = SimulatedCameraFrame.make(from: still.image) else { return }
        resume(suppressing: nil)
        let clock = ContinuousClock()
        let end = clock.now + .seconds(3)
        var time = lastFrameTime
        while clock.now < end, !Task.isCancelled {
            if case .paused = mode { return }
            time += 1.0 / 30
            analyze(frame, at: time)
            try? await Task.sleep(for: .milliseconds(33))
        }
    }
    #endif

    private func analyze(_ frame: CVPixelBuffer, at time: Double) {
        lastFrameTime = time
        if case .paused = mode { return }
        guard let screen else { return }
        let mapper = currentMapper(for: frame, screen: screen)
        guard let region else { return }

        let readings = LumaPlane.read(frame) { decoder.decode($0, region: region, options: .camera) } ?? []
        switch mode {
        case .scanning:
            guard let reading = confirmer.confirm(readings, at: time) else {
                // On a frame with nothing to show, so it never delays a detection.
                if !isWarmedUp {
                    FrozenScanRenderer.warmUp(with: CIImage(cvPixelBuffer: frame))
                    isWarmedUp = true
                }
                return
            }
            mode = .tracking(reading.text)
            tracked = (reading, frame)
            let geometry = ScanFrameGeometry(bufferQuad: Self.outline(of: reading), mapper: mapper)
            continuation?.yield(.detected(ScanDetection(code: ScannedCode(reading), geometry: geometry)))
        case .tracking(let text):
            guard let reading = readings.first(where: { $0.text == text }) else { return }
            tracked = (reading, frame)
            continuation?.yield(.tracked(ScanFrameGeometry(bufferQuad: Self.outline(of: reading), mapper: mapper)))
        case .paused:
            break
        }
    }

    /// The buffer-to-screen mapping, and the region to scan: the viewfinder
    /// plus a margin, in buffer pixels. Recomputed when the frame or screen
    /// size changes.
    private func currentMapper(for frame: CVPixelBuffer, screen: ScannerViewport) -> AspectFillMapper {
        let bufferSize = CGSize(width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
        if let mapper, mapper.bufferSize == bufferSize {
            return mapper
        }
        let mapper = screen.mapper(bufferSize: bufferSize)
        let margin = screen.viewfinder.width * ScannerMetrics.scanMarginFraction
        let rect = mapper.bufferRect(fromView: screen.viewfinder.insetBy(dx: -margin, dy: -margin))
            .intersection(CGRect(origin: .zero, size: bufferSize))
        region = rect.isEmpty ? nil : ScanRegion(
            minX: Int(rect.minX), minY: Int(rect.minY), maxX: Int(rect.maxX.rounded(.up)), maxY: Int(rect.maxY.rounded(.up))
        )
        self.mapper = mapper
        return mapper
    }

    /// The code with room for its quiet zones and printed digits, in buffer pixels.
    private static func outline(of reading: BarcodeReading) -> Quad {
        func point(_ p: BarcodePoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
        let module = reading.moduleSize
        return Quad(
            topLeft: point(reading.topLeft), topRight: point(reading.topRight),
            bottomRight: point(reading.bottomRight), bottomLeft: point(reading.bottomLeft)
        )
        .expanded(
            leading: module * ScannerMetrics.outlineSideModules, trailing: module * ScannerMetrics.outlineSideModules,
            top: module * ScannerMetrics.outlineTopModules, bottom: module * ScannerMetrics.outlineBottomModules
        )
    }
}
