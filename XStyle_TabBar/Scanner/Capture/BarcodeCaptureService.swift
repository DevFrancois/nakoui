@preconcurrency import AVFoundation
import OSLog

/// Owns the camera session. Session calls block, so the actor runs on a
/// serial queue of its own, never the main thread. The session is set up once,
/// on the first start; later runs only start and stop it, the fastest way
/// back to a live camera. Frames go to `analyzer`, which decodes them on the
/// video queue.
actor BarcodeCaptureService {
    /// Shared with the preview layer, which only displays it.
    nonisolated let session = AVCaptureSession()
    nonisolated let analyzer = FrameAnalyzer()

    private nonisolated let sessionQueue = DispatchSerialQueue(label: "dev.kavsoft.XStyle-TabBar.scanner.session")
    private let output = AVCaptureVideoDataOutput()
    private var delegate: VideoFrameDelegate?
    private(set) var device: AVCaptureDevice?
    private var viewport: ScannerViewport?
    /// Identifies the latest run, so a stop that arrives after a newer start
    /// is ignored.
    private var runToken = 0
    private var isRunActive = false
    /// Whether the camera is held stopped without ending the run, such as
    /// under the result sheet; see `setSuspended`.
    private var isSuspended = false
    /// Whether the next resume starts the run's tuning afresh: a run that
    /// started suspended hasn't had its first look at the light yet.
    private var resumeStartsFresh = false
    /// Whether the torch was lit when the camera was suspended.
    private var resumeLightsTorch = false
    private var adjustmentTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    /// What the user can zoom through, and where scanning starts. Set with
    /// the camera on the first start.
    private(set) var zoom: CameraZoom?
    /// Whether the camera has a torch to light codes with. Set with the
    /// camera on the first start.
    private(set) var hasTorch = false

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    /// False in the Simulator, which has no camera.
    nonisolated static var isCameraAvailable: Bool {
        backCamera != nil
    }

    private nonisolated static var backCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Whether there's a camera to scan with, found once set up.
    func hasCamera() -> Bool {
        device != nil || Self.backCamera != nil
    }

    /// Starts the camera, setting it up on first use.
    /// - Returns: The token that stops this run.
    func start() throws -> Int {
        if device == nil {
            try configure()
        }
        runToken += 1
        isRunActive = true
        // Each run starts sharp and looks for flicker afresh.
        if let device, (try? device.lockForConfiguration()) != nil {
            CameraTuning.resetExposure(on: device)
            device.unlockForConfiguration()
        }
        // A suspended run waits for `setSuspended(false)` to start the camera.
        if isSuspended {
            resumeStartsFresh = true
        } else {
            runCamera(startingFresh: true)
        }
        return runToken
    }

    /// Stops the run `token` came from, unless a newer run has started.
    /// - Returns: Whether the camera stopped.
    func stop(_ token: Int) -> Bool {
        guard token == runToken else { return false }
        isRunActive = false
        adjustmentTask?.cancel()
        adjustmentTask = nil
        resumeStartsFresh = false
        resumeLightsTorch = false
        _ = setTorch(false)
        if session.isRunning {
            session.stopRunning()
        }
        return true
    }

    /// Holds the camera stopped without ending the run, or starts it again,
    /// such as while the result sheet covers it. Stopping the session turns
    /// the camera indicator off; resuming only starts it, the quickest way
    /// back to a live camera, keeping the run's exposure, flicker tuning and
    /// torch. Also holds back the next run if none is active.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        guard isRunActive else { return }
        if suspended {
            adjustmentTask?.cancel()
            adjustmentTask = nil
            resumeLightsTorch = device?.torchMode == .on
            _ = setTorch(false)
            if session.isRunning {
                session.stopRunning()
            }
        } else {
            runCamera(startingFresh: resumeStartsFresh)
            resumeStartsFresh = false
            if resumeLightsTorch {
                _ = setTorch(true)
            }
            resumeLightsTorch = false
        }
    }

    /// Starts the session, and the tuning that follows the light.
    private func runCamera(startingFresh: Bool) {
        if !session.isRunning {
            session.startRunning()
        }
        adjustmentTask?.cancel()
        adjustmentTask = Task { await adjustPeriodically(startingFresh: startingFresh) }
    }

    /// Tells the analyzer where the frames are shown, and focuses and meters
    /// on the viewfinder.
    func setViewport(_ viewport: ScannerViewport) async {
        guard viewport.size.width > 0, viewport.size.height > 0,
              self.viewport.map({ viewport.revision >= $0.revision }) ?? true else { return }
        self.viewport = viewport
        await analyzer.setViewport(viewport)
        // The pane resizes on every display frame while the result sheet
        // moves: focus and meter once it has settled, not at each step.
        try? await Task.sleep(for: .seconds(ScannerMetrics.meteringSettleDelay))
        // The actor may have accepted a newer configuration during the hops.
        guard self.viewport?.revision == viewport.revision else { return }
        guard let device else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let bufferSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let mapper = viewport.mapper(bufferSize: bufferSize)
        let rect = mapper.bufferRect(fromView: viewport.viewfinder)
        let deviceRect = CGRect(
            x: rect.minX / bufferSize.width, y: rect.minY / bufferSize.height,
            width: rect.width / bufferSize.width, height: rect.height / bufferSize.height
        )
        guard (try? device.lockForConfiguration()) != nil else { return }
        CameraTuning.meter(on: deviceRect, device: device)
        device.unlockForConfiguration()
    }

    /// Zooms to `factor`, within the camera's range, easing there when
    /// `animated`. Pinch steps come in fast, so they go onto the session queue
    /// in call order instead of through tasks, which may run in any order.
    nonisolated func setZoom(_ factor: Double, animated: Bool) {
        sessionQueue.async {
            self.assumeIsolated { $0.applyZoom(factor, animated: animated) }
        }
    }

    private func applyZoom(_ factor: Double, animated: Bool) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let factor = (device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor).clamp(CGFloat(factor))
        if animated {
            device.ramp(toVideoZoomFactor: factor, withRate: ScannerMetrics.zoomRampRate)
        } else {
            device.videoZoomFactor = factor
        }
        device.unlockForConfiguration()
    }

    /// Whether the torch is lit, now and each time that changes, including
    /// when the system turns it off: when the phone is too hot, the session
    /// is interrupted, or Control Center's flashlight takes over. Ends when
    /// the consuming task is cancelled.
    func torchActivity() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        guard let device, hasTorch else {
            continuation.finish()
            return stream
        }
        let observation = device.observe(\.isTorchActive, options: [.initial, .new]) { device, _ in
            continuation.yield(device.isTorchActive)
        }
        continuation.onTermination = { _ in
            observation.invalidate()
        }
        return stream
    }

    /// Turns the torch on or off; it only turns on during a run.
    /// - Returns: Whether the torch is on. It can't turn on while the
    ///   system holds it back, such as when the phone is too hot.
    func setTorch(_ isOn: Bool) -> Bool {
        guard let device, hasTorch, (try? device.lockForConfiguration()) != nil else { return false }
        defer { device.unlockForConfiguration() }
        guard isOn else {
            device.torchMode = .off
            return false
        }
        guard isRunActive, device.isTorchAvailable else { return false }
        return (try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)) != nil
    }

    private func configure() throws {
        // A failed attempt leaves nothing on the session, so a retry starts clean.
        guard let device = Self.backCamera else { throw BarcodeCaptureError.noCamera }
        guard let format = CameraFormatPicker.bestFormat(for: device) else { throw BarcodeCaptureError.noFormat }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        guard session.canAddInput(input) else { throw BarcodeCaptureError.cannotAddInput }
        session.addInput(input)

        // Ask for full-range 4:2:0 explicitly: the device's native format can
        // be a compressed one the CPU must not read.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.automaticallyConfiguresOutputBufferDimensions = false
        output.deliversPreviewSizedOutputBuffers = false
        if output.isDeferredStartSupported {
            output.isDeferredStartEnabled = false
        }
        let delegate = VideoFrameDelegate(analyzer: analyzer)
        output.setSampleBufferDelegate(delegate, queue: analyzer.queue)
        self.delegate = delegate
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw BarcodeCaptureError.cannotAddOutput
        }
        session.addOutput(output)

        // Unrotated buffers (rotating them costs a copy) and no stabilization,
        // which adds latency and would shift frames away from the preview.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }

        // Scanning still works on the camera's defaults if this one fails.
        if (try? device.lockForConfiguration()) != nil {
            CameraTuning.apply(format, to: device)
            device.videoZoomFactor = CameraTuning.zoom(for: device).initial
            device.unlockForConfiguration()
        }
        // Read without the lock, so the controls show even if it failed; the
        // model applies the starting zoom again on the first run.
        zoom = CameraTuning.zoom(for: device)
        hasTorch = device.hasTorch && device.isTorchModeSupported(.on)
        self.device = device
        recoveryTask = Task { await recoverFromRuntimeErrors() }
    }

    /// Restarts the session if a runtime error, such as a media services
    /// reset, stops it while a run is active.
    private func recoverFromRuntimeErrors() async {
        for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.runtimeErrorNotification, object: session) {
            if isRunActive && !isSuspended && !session.isRunning {
                session.startRunning()
            }
        }
    }

    /// Ten times a second, exposes for whole pulses under flickering light;
    /// twice a second, eases the exposure cap in dim light and fits the frame
    /// rate to the exposure and thermal pressure. A resume carries on with
    /// the flicker the run found.
    private func adjustPeriodically(startingFresh: Bool) async {
        if startingFresh {
            await analyzer.resetFlicker()
        }
        var tick = 0
        #if DEBUG
        var lastMode = ""
        #endif
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            let flicker = await analyzer.lightFlicker
            // Checked after the last wait, which a stop can end early or run
            // during: going on would set the exposure of a stopped run, or of
            // the next one.
            guard !Task.isCancelled else { break }
            tick += 1
            guard let device, (try? device.lockForConfiguration()) != nil else { continue }
            if flicker != .steady {
                CameraTuning.exposeForWholePulses(device, flicker: flicker)
            }
            if tick % 5 == 0 {
                CameraTuning.adjust(device, flicker: flicker)
            }
            let exposesWholePulses = CameraTuning.exposesWholePulses(device)
            #if DEBUG
            // Only when the mode changes, so the console stays quiet under
            // lamps that always flicker.
            let mode = "\(flicker), \(exposesWholePulses ? "whole-pulse" : "auto") exposure"
            let report = mode == lastMode ? nil : String(
                format: "%@ %.2f ms at ISO %.0f, %.0f fps", mode,
                device.exposureDuration.seconds * 1000, device.iso, 1 / device.activeVideoMaxFrameDuration.seconds
            )
            lastMode = mode
            #endif
            device.unlockForConfiguration()
            await analyzer.setExposesWholePulses(exposesWholePulses)
            #if DEBUG
            if let report {
                Self.logger.debug("Light: \(report)")
            }
            #endif
        }
    }

    #if DEBUG
    private static let logger = Logger(subsystem: "dev.kavsoft.XStyle-TabBar", category: "scanner")
    #endif
}
