@preconcurrency import AVFoundation

/// Camera settings for scanning. Most blur and latency come from the camera's
/// defaults, not the decoder: long exposures smear a moving code, video HDR
/// merges two exposures, and smooth focus is slow. Every function expects the
/// device to be locked for configuration.
nonisolated enum CameraTuning {
    static let frameRate: Int32 = 60
    /// The exposure cap's steps. It starts short to freeze motion, and
    /// lengthens only when the camera runs out of ISO in dim light.
    private static let exposureSteps = [250, 180, 120, 60].map { CMTime(value: 1, timescale: $0) }

    /// Call after the input is added: adding it resets frame durations.
    static func apply(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        device.activeFormat = format
        if device.isAutoVideoFrameRateEnabled {
            device.isAutoVideoFrameRateEnabled = false
        }

        if format.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
        }
        // Low-light boost lengthens exposures and drops frames as it toggles.
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            // These take effect when the focus mode is next set.
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = false
            }
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            device.isFaceDrivenAutoFocusEnabled = false
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.automaticallyAdjustsFaceDrivenAutoExposureEnabled = false
            device.isFaceDrivenAutoExposureEnabled = false
            device.exposureMode = .continuousAutoExposure
        }
        resetExposure(on: device)
    }

    /// The start of a run: auto exposure under the shortest cap, at the full
    /// frame rate. In that order, so no exposure outlasts a frame.
    static func resetExposure(on device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
            device.activeMaxExposureDuration = clamped(exposureSteps[0], to: device.activeFormat)
        }
        setFrameRate(frameRate, on: device)
    }

    /// Focuses and meters on the viewfinder, given in capture-device
    /// coordinates (0 to 1 across the unrotated sensor).
    static func meter(on rect: CGRect, device: AVCaptureDevice) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if device.isFocusRectOfInterestSupported {
            device.focusRectOfInterest = rect.expanded(toAtLeast: device.minFocusRectOfInterestSize)
        } else if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = center
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureRectOfInterestSupported {
            device.exposureRectOfInterest = rect.expanded(toAtLeast: device.minExposureRectOfInterestSize)
        } else if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = center
        }
        // Exposures set for flickering light stay; the meter still follows the rect.
        if device.exposureMode != .custom, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    /// The zoom range for the active format, with a preset where the smallest
    /// product barcode is sharp at the closest focus distance (see
    /// `BarcodeZoom`), rounded to the tenth the zoom buttons show.
    static func zoom(for device: AVCaptureDevice) -> CameraZoom {
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let shortSide = Double(min(dimensions.width, dimensions.height))
        let longSide = Double(max(dimensions.width, dimensions.height))
        let minimum = Double(device.minAvailableVideoZoomFactor)
        let maximum = max(minimum, min(Double(device.maxAvailableVideoZoomFactor), ScannerMetrics.maximumZoom))
        let recommended = BarcodeZoom.recommendedFactor(
            minimumFocusDistance: Double(device.minimumFocusDistance),
            fieldOfView: Double(format.videoFieldOfView),
            formatAspect: longSide > 0 ? shortSide / longSide : 0,
            codeWidth: ScannerMetrics.minimumCodeWidth,
            fill: ScannerMetrics.viewfinderWidthFraction * ScannerMetrics.minimumCodeViewfinderFill,
            maximum: min(maximum, ScannerMetrics.maximumAutoZoom)
        )
        return CameraZoom(range: minimum...maximum, recommended: (recommended * 10).rounded() / 10)
    }

    /// Lengthens the exposure cap a step when the camera is out of ISO and
    /// still underexposed, under steady light; flickering light is handled by
    /// `exposeForWholePulses`. Fits the frame rate to the exposure, and lowers
    /// it under thermal pressure.
    static func adjust(_ device: AVCaptureDevice, flicker: LightFlicker) {
        let format = device.activeFormat
        if flicker == .steady, device.exposureMode == .custom, device.isExposureModeSupported(.continuousAutoExposure) {
            // Left from flickering light, such as by an earlier run: a fixed
            // exposure would no longer follow the scene.
            device.exposureMode = .continuousAutoExposure
        }
        let isAutoExposing = device.exposureMode == .continuousAutoExposure
        var exposure = device.exposureMode == .custom ? device.exposureDuration : device.activeMaxExposureDuration
        if flicker == .steady, isAutoExposing {
            let steps = exposureSteps.map { clamped($0, to: format) }
            // Matched within a tenth of a millisecond, in case the device rounds the cap.
            if let index = steps.firstIndex(where: { abs($0.seconds - exposure.seconds) < 0.0001 }) {
                if device.iso >= format.maxISO * 0.95, device.exposureTargetOffset < -1, index + 1 < steps.count {
                    exposure = steps[index + 1]
                }
            } else {
                exposure = steps[0]
            }
        }
        fitFrameRate(to: exposure, isWhole: device.exposureMode == .custom, on: device)
        if flicker == .steady, isAutoExposing, exposure != device.activeMaxExposureDuration,
           CMTimeCompare(exposure, device.activeVideoMaxFrameDuration) <= 0 {
            device.activeMaxExposureDuration = exposure
        }
    }

    /// Under flickering light, exposes for whole pulses, so every sensor row
    /// sees the same light and no bands show. Auto exposure would shorten
    /// them whenever it has light to spare, so the exposure is set here and
    /// the camera's meter steers only the ISO; auto exposure stops short of
    /// a whole pulse even under a one-pulse cap. Only in light too bright for
    /// one pulse, such as outdoors, does auto exposure keep going, under that
    /// cap. Call often: each call takes one metering step.
    static func exposeForWholePulses(_ device: AVCaptureDevice, flicker: LightFlicker) {
        let format = device.activeFormat
        let pulse = 1 / Double(ScannerMetrics.flickerRate)
        guard device.isExposureModeSupported(.custom), device.isExposureModeSupported(.continuousAutoExposure) else { return }
        let isCustom = device.exposureMode == .custom

        // The light the meter asks for, in ISO-seconds, moved halfway toward
        // its target each call so it settles without overshooting.
        var light = Double(device.iso) * device.exposureDuration.seconds
        // Nothing to go on before the first frames.
        guard light.isFinite, light > 0 else { return }
        let offset = Double(device.exposureTargetOffset)
        if abs(offset) > ScannerMetrics.flickerMeteringDeadband {
            light *= pow(2, -offset / 2)
        }
        func iso(_ count: Int) -> Double { light / (Double(count) * pulse) }
        let minimumISO = Double(format.minISO), maximumISO = Double(format.maxISO)

        // Too bright for even one pulse, such as outdoors: auto exposure goes
        // shorter under a one-pulse cap. It takes over below half the lowest
        // ISO and hands back only at the lowest, so it doesn't hop.
        guard iso(1) >= (isCustom ? minimumISO / 2 : minimumISO) else {
            if device.exposureMode != .continuousAutoExposure {
                device.exposureMode = .continuousAutoExposure
            }
            let cap = clamped(pulses(1), to: format)
            if device.activeMaxExposureDuration != cap, CMTimeCompare(cap, device.activeVideoMaxFrameDuration) <= 0 {
                device.activeMaxExposureDuration = cap
            }
            return
        }
        var count = flicker.minimumPulses
        // Dim light: a second pulse before the ISO runs out, and back to one
        // only with room to spare, so it doesn't hop between them.
        let isOnTwoPulses = isCustom && device.exposureDuration.seconds > pulse * 1.5
        if count == 1, iso(1) > maximumISO || (isOnTwoPulses && iso(1) > maximumISO / 2) {
            count = 2
        }
        // Bright light: one pulse rather than overexposing two.
        if count == 2, iso(2) < minimumISO {
            count = 1
        }

        var duration = clamped(pulses(count), to: format)
        func fitsFrames() -> Bool {
            duration.seconds * wholeExposureFrameMargin <= device.activeVideoMaxFrameDuration.seconds
        }
        if !fitsFrames() {
            // Longer frames first. Shorter ones wait for `adjust` to see the
            // shorter exposure in place.
            fitFrameRate(to: duration, isWhole: true, on: device)
            if !fitsFrames() {
                count = 1
                duration = clamped(pulses(1), to: format)
            }
        }
        let target = min(max(iso(count), minimumISO), maximumISO)
        let isSettled = isCustom
            && abs(device.exposureDuration.seconds - duration.seconds) < 0.0001
            && abs(Double(device.iso) - target) <= target * 0.02
        if !isSettled {
            device.setExposureModeCustom(duration: duration, iso: Float(target), completionHandler: nil)
        }
    }

    /// Whether the camera exposes for whole pulses, set by `exposeForWholePulses`.
    static func exposesWholePulses(_ device: AVCaptureDevice) -> Bool {
        let count = device.exposureDuration.seconds * Double(ScannerMetrics.flickerRate)
        return device.exposureMode == .custom && count >= 0.95 && abs(count - count.rounded()) < 0.02
    }

    private static func pulses(_ count: Int) -> CMTime {
        CMTime(value: CMTimeValue(count), timescale: Int32(ScannerMetrics.flickerRate))
    }

    /// A frame can't be exposed for its whole length: at 50 fps the camera
    /// stopped two-pulse exposures at 19.77 ms instead of 20. Exposures that
    /// must last whole pulses get frames this much longer than they are.
    private static let wholeExposureFrameMargin = 1.05

    /// The full frame rate, or less: under thermal pressure, and so a frame
    /// outlasts its exposure, such as 47 fps for two whole 100 Hz pulses.
    private static func fitFrameRate(to exposure: CMTime, isWhole: Bool, on device: AVCaptureDevice) {
        let thermalRate: Int32 = switch device.systemPressureState.level {
        case .serious: 30
        case .critical: 20
        default: frameRate
        }
        let frameDuration = exposure.seconds * (isWhole ? wholeExposureFrameMargin : 1)
        let exposureRate = frameDuration > 0 ? Int32((1 / frameDuration + 0.01).rounded(.down)) : frameRate
        setFrameRate(min(thermalRate, exposureRate), on: device)
    }

    private static func setFrameRate(_ rate: Int32, on device: AVCaptureDevice) {
        // An unsupported rate raises an exception Swift can't catch.
        let isSupported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(rate) && Double(rate) <= $0.maxFrameRate
        }
        let duration = CMTime(value: 1, timescale: rate)
        if isSupported, device.activeVideoMinFrameDuration != duration {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    private static func clamped(_ time: CMTime, to format: AVCaptureDevice.Format) -> CMTime {
        CMTimeMaximum(format.minExposureDuration, CMTimeMinimum(time, format.maxExposureDuration))
    }
}
