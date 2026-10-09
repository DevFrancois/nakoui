@preconcurrency import AVFoundation

/// Camera settings for scanning. Most blur and latency come from the camera's
/// defaults, not the decoder: long exposures smear a moving code, video HDR
/// merges two exposures, and smooth focus is slow. Every function expects the
/// device to be locked for configuration.
nonisolated enum CameraTuning {
    static let frameRate: Int32 = 60
    /// The exposure cap's steps. It starts short to freeze motion, and
    /// lengthens only when the camera runs out of ISO in dim light.
    private static let exposureSteps: [Int32] = [250, 180, 120, 60]

    /// Call after the input is added: adding it resets frame durations.
    static func apply(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        device.activeFormat = format
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        if device.isAutoVideoFrameRateEnabled {
            device.isAutoVideoFrameRateEnabled = false
        }
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

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
            device.activeMaxExposureDuration = clamped(CMTime(value: 1, timescale: exposureSteps[0]), to: format)
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

    /// Zooms so the smallest product barcode is sharp at the closest focus
    /// distance (see `BarcodeZoom`).
    static func applyZoom(to device: AVCaptureDevice) {
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let shortSide = Double(min(dimensions.width, dimensions.height))
        let longSide = Double(max(dimensions.width, dimensions.height))
        device.videoZoomFactor = BarcodeZoom.recommendedFactor(
            minimumFocusDistance: Double(device.minimumFocusDistance),
            fieldOfView: Double(format.videoFieldOfView),
            formatAspect: longSide > 0 ? shortSide / longSide : 0,
            codeWidth: ScannerMetrics.minimumCodeWidth,
            fill: ScannerMetrics.viewfinderWidthFraction * ScannerMetrics.minimumCodeViewfinderFill,
            maximum: min(Double(device.maxAvailableVideoZoomFactor), ScannerMetrics.maximumAutoZoom)
        )
    }

    /// Lengthens the exposure cap a step when the camera is out of ISO and
    /// still underexposed; drops the frame rate under thermal pressure.
    static func adjust(_ device: AVCaptureDevice) {
        let format = device.activeFormat
        if device.exposureMode == .continuousAutoExposure,
           device.iso >= format.maxISO * 0.95, device.exposureTargetOffset < -1,
           let next = exposureSteps.map({ CMTime(value: 1, timescale: $0) })
               .first(where: { CMTimeCompare($0, device.activeMaxExposureDuration) > 0 }) {
            device.activeMaxExposureDuration = clamped(next, to: format)
        }

        let rate: Int32
        switch device.systemPressureState.level {
        case .serious: rate = 30
        case .critical: rate = 20
        default: rate = frameRate
        }
        // An unsupported rate raises an exception Swift can't catch.
        let isSupported = format.videoSupportedFrameRateRanges.contains {
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
