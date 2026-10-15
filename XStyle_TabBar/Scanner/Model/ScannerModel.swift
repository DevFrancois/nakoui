@preconcurrency import AVFoundation
import Observation

/// Drives the Scan tab: camera access, the capture run, and the found-code
/// animation through to the result sheet. The camera and the decoding live in
/// `BarcodeCaptureService`; this holds only what the views read.
@Observable
final class ScannerModel {
    private(set) var state: ScannerState
    /// The found-code animation, from the first sighting until the result has closed.
    private(set) var reveal: ScanReveal?
    /// The code in the result sheet.
    var scannedCode: ScannedCode?
    /// The live session, for the preview layer. Nil until the camera first
    /// starts, and always in previews and the Simulator.
    private(set) var session: AVCaptureSession?
    /// The camera's zoom range, for the zoom control. Nil until the camera
    /// first starts.
    private(set) var zoom: CameraZoom?
    /// The zoom the camera is at, or heading to.
    private(set) var zoomFactor = 1.0
    /// Read when timing the result sheet; the view keeps it current.
    @ObservationIgnored var reduceMotion = false

    /// Made on the first run, so creating the model costs nothing at launch.
    @ObservationIgnored private var capture: BarcodeCaptureService?
    /// Decodes the frames: the camera's, or the simulated camera's.
    @ObservationIgnored private var analyzer: FrameAnalyzer?
    @ObservationIgnored private var screenSize = CGSize.zero
    @ObservationIgnored private var displayScale: CGFloat = 3
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    init(state: ScannerState = .idle, scannedCode: ScannedCode? = nil, zoom: CameraZoom? = nil) {
        self.state = state
        self.scannedCode = scannedCode
        self.zoom = zoom
        zoomFactor = zoom?.recommended ?? 1
    }

    private var viewfinder: CGRect {
        ScannerMetrics.viewfinderRect(in: CGRect(origin: .zero, size: screenSize))
    }

    /// Runs the camera until the calling task is cancelled.
    func run() async {
        guard BarcodeCaptureService.isCameraAvailable else {
            #if targetEnvironment(simulator)
            await runSimulatedCamera()
            #else
            state = .unavailable
            #endif
            return
        }
        guard await isCameraAuthorized() else {
            state = .denied
            return
        }
        // The tab may have been left while the permission prompt was up.
        guard !Task.isCancelled else { return }

        let capture = capture ?? BarcodeCaptureService()
        self.capture = capture
        analyzer = capture.analyzer
        let events = await capture.analyzer.events()
        let token: Int
        do {
            token = try await capture.start()
        } catch {
            state = .unavailable
            return
        }
        session = capture.session
        // The camera keeps its zoom between runs, so only the first sets it.
        if zoom == nil, let cameraZoom = await capture.zoom {
            zoom = cameraZoom
            zoomFactor = cameraZoom.recommended
        }
        state = .scanning
        await capture.setScreen(size: screenSize, viewfinder: viewfinder, displayScale: displayScale)
        if reveal == nil && scannedCode == nil {
            await capture.analyzer.resume(suppressing: nil)
        }

        // Ends when the task is cancelled, such as on leaving the tab.
        for await event in events {
            handle(event)
        }
        if await capture.stop(token) {
            state = .idle
        }
    }

    /// The full-screen size the camera is shown at, which places the
    /// viewfinder and maps codes onto the screen.
    func updateScreen(size: CGSize, displayScale: CGFloat) {
        guard size != screenSize || displayScale != self.displayScale else { return }
        screenSize = size
        self.displayScale = displayScale
        let viewfinder = viewfinder
        if let capture {
            Task {
                await capture.setScreen(size: size, viewfinder: viewfinder, displayScale: displayScale)
            }
        } else if let analyzer {
            Task {
                await analyzer.setScreen(size: size, viewfinder: viewfinder, displayScale: displayScale)
            }
        }
    }

    /// Zooms the camera, within its range: straight there for pinch steps,
    /// easing there for the zoom buttons.
    func setZoom(_ factor: Double, animated: Bool) {
        guard let zoom else { return }
        zoomFactor = zoom.range.clamp(factor)
        capture?.setZoom(zoomFactor, animated: animated)
    }

    /// Call once the result sheet is gone: the reveal fades and scanning
    /// resumes, holding the same code back until it leaves the frame.
    func resultDidClose() {
        guard let code = reveal?.code else { return }
        reveal?.close()
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(ScanRevealTimeline.closeDuration))
            guard !Task.isCancelled else { return }
            reveal = nil
            await analyzer?.resume(suppressing: code.decoderText)
        }
    }

    #if targetEnvironment(simulator)
    /// The Simulator has no camera: frames are fed to the real analyzer by
    /// Simulate Scan instead, so everything past the camera runs for real.
    private func runSimulatedCamera() async {
        let analyzer = analyzer ?? FrameAnalyzer()
        self.analyzer = analyzer
        let events = await analyzer.events()
        await analyzer.setScreen(size: screenSize, viewfinder: viewfinder, displayScale: displayScale)
        state = .scanning
        for await event in events {
            handle(event)
        }
    }

    /// Shows the simulated camera the backdrop's barcode label until it's
    /// decoded and revealed.
    func simulateScan() {
        guard reveal == nil, scannedCode == nil, let analyzer,
              let still = SimulatedStill.render(screenSize: screenSize) else { return }
        Task {
            await analyzer.playSimulatedCamera(still)
        }
    }
    #endif

    private func handle(_ event: ScanEvent) {
        switch event {
        case .detected(let detection):
            guard reveal == nil, scannedCode == nil, let analyzer else { return }
            reveal = ScanReveal(code: detection.code, viewfinder: Quad(viewfinder), liveQuad: detection.quad)
            playReveal { await analyzer.freeze() }
        case .tracked(let quad):
            guard let current = reveal, current.frozen == nil else { return }
            // A little smoothing against jitter between frames.
            reveal?.liveQuad = current.liveQuad.lerp(to: quad, 0.6)
        }
    }

    /// Freezes the frame on time, then brings up the result as the icon settles.
    private func playReveal(freeze: @escaping () async -> FrozenScan?) {
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(ScanRevealTimeline.freeze))
            guard !Task.isCancelled else { return }
            if let frozen = await freeze() {
                reveal?.freeze(frozen)
            }
            guard let current = reveal else { return }
            if let freezeTime = current.freezeTime {
                let resultTime = ScanRevealTimeline.resultTime(freezeTime: freezeTime, reduceMotion: reduceMotion)
                try? await Task.sleep(for: .seconds(max(current.startDate.addingTimeInterval(resultTime).timeIntervalSinceNow, 0)))
                guard !Task.isCancelled else { return }
            }
            scannedCode = current.code
        }
    }

    private func isCameraAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}
