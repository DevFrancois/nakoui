@preconcurrency import AVFoundation

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

    /// Starts the camera, setting it up on first use.
    /// - Returns: The token that stops this run.
    func start() throws -> Int {
        if device == nil {
            try configure()
        }
        runToken += 1
        isRunActive = true
        if !session.isRunning {
            session.startRunning()
        }
        adjustmentTask?.cancel()
        adjustmentTask = Task { await adjustPeriodically() }
        return runToken
    }

    /// Stops the run `token` came from, unless a newer run has started.
    /// - Returns: Whether the camera stopped.
    func stop(_ token: Int) -> Bool {
        guard token == runToken else { return false }
        isRunActive = false
        adjustmentTask?.cancel()
        adjustmentTask = nil
        _ = setTorch(false)
        if session.isRunning {
            session.stopRunning()
        }
        return true
    }

    /// Tells the analyzer where the frames are shown, and focuses and meters
    /// on the viewfinder.
    func setViewport(_ viewport: ScannerViewport) async {
        guard viewport.size.width > 0, viewport.size.height > 0,
              self.viewport.map({ viewport.revision >= $0.revision }) ?? true else { return }
        self.viewport = viewport
        await analyzer.setViewport(viewport)
        // The actor may have accepted a newer configuration during the hop.
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
            if isRunActive && !session.isRunning {
                session.startRunning()
            }
        }
    }

    /// Twice a second, eases the exposure cap in dim light and the frame
    /// rate under thermal pressure.
    private func adjustPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard let device, (try? device.lockForConfiguration()) != nil else { continue }
            CameraTuning.adjust(device)
            device.unlockForConfiguration()
        }
    }
}
