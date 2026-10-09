@preconcurrency import AVFoundation

/// Receives frames from the video output and hands them to the analyzer.
/// The output calls back on the analyzer's own queue, so this enters its
/// isolation synchronously.
nonisolated final class VideoFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private let analyzer: FrameAnalyzer

    init(analyzer: FrameAnalyzer) {
        self.analyzer = analyzer
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Already on the analyzer's queue, and the buffer is only used during
        // this call, so handing it over can't race.
        nonisolated(unsafe) let sampleBuffer = sampleBuffer
        analyzer.assumeIsolated { analyzer in
            analyzer.analyze(sampleBuffer)
        }
    }
}
