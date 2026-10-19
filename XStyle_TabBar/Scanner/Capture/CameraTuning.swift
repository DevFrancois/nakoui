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
    /// The steps under flickering light: one pulse, then two. Exposures of
    /// whole pulses catch the same light in every sensor row, so no bands.
    private static let flickerExposureSteps = (1...2).map { CMTime(value: $0, timescale: Int32(ScannerMetrics.flickerRate)) }

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

    /// The start of a run: the shortest exposure cap at the full frame rate.
    static func resetExposure(on device: AVCaptureDevice) {
        setFrameRate(frameRate, on: device)
        if device.exposureMode == .continuousAutoExposure {
            device.activeMaxExposureDuration = clamped(exposureSteps[0], to: device.activeFormat)
        }
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
        if device.isExposureModeSupported(.continuousAutoExposure) {
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

    /// Moves the exposure cap to whole pulses once the light is seen
    /// flickering, and lengthens it a step when the camera is out of ISO and
    /// still underexposed. Lowers the frame rate for exposures longer than a
    /// frame and under thermal pressure.
    static func adjust(_ device: AVCaptureDevice, isLightFlickering: Bool) {
        let format = device.activeFormat
        let isAutoExposing = device.exposureMode == .continuousAutoExposure
        let steps = (isLightFlickering ? flickerExposureSteps : exposureSteps).map { clamped($0, to: format) }
        var cap = device.activeMaxExposureDuration
        if isAutoExposing {
            // Matched within a tenth of a millisecond, in case the device rounds the cap.
            if let index = steps.firstIndex(where: { abs($0.seconds - cap.seconds) < 0.0001 }) {
                if device.iso >= format.maxISO * 0.95, device.exposureTargetOffset < -1, index + 1 < steps.count {
                    cap = steps[index + 1]
                }
            } else {
                // The light was just seen flickering: start on its ladder.
                cap = steps[0]
            }
        }

        let thermalRate: Int32 = switch device.systemPressureState.level {
        case .serious: 30
        case .critical: 20
        default: frameRate
        }
        // A frame lasts at least its exposure: two 100 Hz pulses need 50 fps.
        let exposureRate = cap.seconds > 0 ? Int32((1 / cap.seconds + 0.01).rounded(.down)) : frameRate
        setFrameRate(min(thermalRate, exposureRate), on: device)

        if isAutoExposing, cap != device.activeMaxExposureDuration,
           CMTimeCompare(cap, device.activeVideoMaxFrameDuration) <= 0 {
            device.activeMaxExposureDuration = cap
        }
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
