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
    private(set) var cameraDevice: AVCaptureDevice?
    /// The camera's zoom range, for the zoom control. Nil until the camera
    /// first starts.
    private(set) var zoom: CameraZoom?
    /// The zoom the camera is at, or heading to.
    private(set) var zoomFactor = 1.0
    /// Whether the camera has a torch, for the flashlight button. False
    /// until the camera first starts.
    private(set) var hasTorch: Bool
    /// Whether the torch is on, or about to be after a tap.
    private(set) var isTorchOn = false
    /// Read when timing the result sheet; the view keeps it current.
    @ObservationIgnored var reduceMotion = false

    /// Made on the first run, so creating the model costs nothing at launch.
    @ObservationIgnored private var capture: BarcodeCaptureService?
    /// Decodes the frames: the camera's, or the simulated camera's.
    @ObservationIgnored private var analyzer: FrameAnalyzer?
    @ObservationIgnored private var screenSize = CGSize.zero
    @ObservationIgnored private var displayScale: CGFloat = 3
    @ObservationIgnored private var previewRotation: CameraImageRotation?
    @ObservationIgnored private var viewportRevision: UInt64 = 0
    @ObservationIgnored private var latestViewport: ScannerViewport?
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    /// The latest torch switch. Each waits for the one before, so quick taps
    /// land in order.
    @ObservationIgnored private var torchTask: Task<Void, Never>?
    /// Counts torch taps, and those the camera has acted on, so only the
    /// latest decides the button, and the device's own changes wait for it.
    @ObservationIgnored private var torchRequest = 0
    @ObservationIgnored private var completedTorchRequest = 0
    /// The last button ease: where it began, and when. A pinch during it
    /// starts from where the camera has reached, not from its target.
    @ObservationIgnored private var zoomRamp: (from: Double, start: Date)?

    init(state: ScannerState = .idle, scannedCode: ScannedCode? = nil, zoom: CameraZoom? = nil, hasTorch: Bool = false) {
        self.state = state
        self.scannedCode = scannedCode
        self.zoom = zoom
        self.hasTorch = hasTorch
        zoomFactor = zoom?.initial ?? 1
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
        cameraDevice = await capture.device
        // The camera keeps its zoom between runs, so only the first sets it.
        // The camera was set to it already, unless that failed.
        if zoom == nil, let cameraZoom = await capture.zoom {
            zoom = cameraZoom
            setZoom(cameraZoom.initial, animated: false)
        }
        hasTorch = await capture.hasTorch
        let torchActivity = await capture.torchActivity()
        let torchTracking = Task {
            for await isActive in torchActivity {
                torchDidChange(isActive)
            }
        }
        defer { torchTracking.cancel() }
        state = .scanning
        publishViewport()
        if reveal == nil && scannedCode == nil {
            await capture.analyzer.resume(suppressing: nil)
        }

        // Ends when the task is cancelled, such as on leaving the tab.
        for await event in events {
            handle(event)
        }
        if await capture.stop(token) {
            state = .idle
            // Stopping turned the torch off.
            isTorchOn = false
        }
    }

    /// The full-screen size the camera is shown at, which places the
    /// viewfinder and maps codes onto the screen.
    func updateScreen(size: CGSize, displayScale: CGFloat) {
        guard size != screenSize || displayScale != self.displayScale else { return }
        screenSize = size
        self.displayScale = displayScale
        publishViewport()
    }

    /// The preview's native coordinator, not the window's dimensions, defines
    /// how raw camera pixels are oriented in this scene.
    func updatePreviewRotation(_ rotation: CameraImageRotation) {
        guard previewRotation != rotation else { return }
        previewRotation = rotation
        if var current = reveal, current.frozen == nil {
            current.geometry = current.geometry.reoriented(to: rotation)
            reveal = current
        }
        publishViewport()
    }

    private func publishViewport() {
        guard let previewRotation, screenSize.width > 0, screenSize.height > 0 else { return }
        viewportRevision &+= 1
        let viewport = ScannerViewport(size: screenSize, viewfinder: viewfinder, displayScale: displayScale,
                                       rotation: previewRotation, revision: viewportRevision)
        latestViewport = viewport
        if let capture {
            Task {
                await capture.setViewport(viewport)
            }
        } else if let analyzer {
            Task {
                await analyzer.setViewport(viewport)
            }
        }
    }

    /// A scene can move to another display without changing its point size.
    func updateDisplayScale(_ displayScale: CGFloat) {
        updateScreen(size: screenSize, displayScale: displayScale)
    }

    /// Zooms the camera, within its range: straight there for pinch steps,
    /// easing there for the zoom buttons.
    func setZoom(_ factor: Double, animated: Bool) {
        guard let zoom else { return }
        zoomRamp = animated ? (liveZoomFactor, .now) : nil
        zoomFactor = zoom.range.clamp(factor)
        capture?.setZoom(zoomFactor, animated: animated)
    }

    /// Where the camera's zoom is now: partway to `zoomFactor` while a button
    /// eases it there at `ScannerMetrics.zoomRampRate` doublings a second.
    var liveZoomFactor: Double {
        guard let zoomRamp else { return zoomFactor }
        let elapsed = Date.now.timeIntervalSince(zoomRamp.start)
        let change = pow(2, Double(ScannerMetrics.zoomRampRate) * elapsed)
        return zoomFactor > zoomRamp.from
            ? min(zoomRamp.from * change, zoomFactor)
            : max(zoomRamp.from / change, zoomFactor)
    }

    /// Turns the flashlight on or off. The button changes at once, then
    /// shows what the camera did, such as staying off when it can't light.
    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    /// Lights or dims the flashlight, in order with taps on the button.
    private func setTorch(_ isOn: Bool) {
        isTorchOn = isOn
        torchRequest += 1
        let request = torchRequest
        let previous = torchTask
        torchTask = Task {
            await previous?.value
            let isActive = await capture?.setTorch(isOn) ?? isOn
            completedTorchRequest = request
            // A later tap is still on its way and has its own say.
            if request == torchRequest {
                isTorchOn = isActive
            }
        }
    }

    /// The device lit or dimmed the torch, possibly on its own. Waits while
    /// taps are on their way, so their changes don't flicker the button.
    private func torchDidChange(_ isActive: Bool) {
        guard completedTorchRequest == torchRequest else { return }
        isTorchOn = isActive
    }

    /// Clears the result and scans again.
    func scanAgain() {
        scannedCode = nil
        resultDidClose()
    }

    /// Call once the result is gone: the reveal fades and scanning resumes,
    /// holding the same code back until it leaves the frame.
    private func resultDidClose() {
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
        // A camera's controls, so they can be tried here too.
        if zoom == nil {
            zoom = CameraZoom(range: 1...5, recommended: 2.6)
            zoomFactor = zoom?.initial ?? 1
        }
        hasTorch = true
        previewRotation = .simulated
        publishViewport()
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
            reveal = ScanReveal(code: detection.code, geometry: previewRotation.map { detection.geometry.reoriented(to: $0) } ?? detection.geometry)
            playReveal { await analyzer.freeze(viewport: self.latestViewport) }
        case .tracked(let geometry):
            guard let current = reveal, current.frozen == nil else { return }
            // A little smoothing against jitter between frames.
            let projected = previewRotation.map { geometry.reoriented(to: $0) } ?? geometry
            reveal?.geometry = current.geometry.interpolated(to: projected, fraction: 0.6)
        }
    }

    /// Freezes the frame on time, then brings up the result as the icon settles.
    private func playReveal(freeze: @escaping () async -> FrozenScan?) {
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(ScanRevealTimeline.freeze))
            guard !Task.isCancelled else { return }
            let frozen = await freeze()
            guard !Task.isCancelled else { return }
            // The found frame is captured, lit if the torch was on; the
            // flashlight isn't needed for the result.
            if isTorchOn {
                setTorch(false)
            }
            if let frozen {
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
