@preconcurrency import AVFoundation

/// Chooses the camera format for scanning.
nonisolated enum CameraFormatPicker {
    /// A 1920x1080 full-range 4:2:0 format reaching `frameRate`. Prefers
    /// phase-detection autofocus, the plain format over slow-motion ones (the
    /// lowest maximum rate that's enough), unbinned pixels, and headroom for
    /// zoom without upscaling. 1080p resolves small codes' bars without 4K's
    /// cost, and 60 fps halves the wait for the next frame.
    static func bestFormat(for device: AVCaptureDevice, frameRate: Double = 60) -> AVCaptureDevice.Format? {
        device.formats
            .filter { format in
                let description = format.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                return dimensions.width == 1920 && dimensions.height == 1080
                    && CMFormatDescriptionGetMediaSubType(description) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= frameRate }
            }
            .max { score($0, frameRate: frameRate) < score($1, frameRate: frameRate) }
    }

    private static func score(_ format: AVCaptureDevice.Format, frameRate: Double) -> Double {
        var score = 0.0
        if format.autoFocusSystem == .phaseDetection {
            score += 100
        }
        let maximumRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        score -= (maximumRate - frameRate) / 10
        if !format.isVideoBinned {
            score += 5
        }
        score += Double(format.videoZoomFactorUpscaleThreshold)
        return score
    }
}
