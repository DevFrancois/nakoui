import Foundation
import Testing
@testable import XStyle_TabBar

struct FlickerDetectorTests {
    /// A camera frame of a textured scene. Under flickering light each row
    /// is lit by the lamp at the moment the rolling shutter reads it.
    private struct Scene {
        static let width = 320
        static let height = 180
        /// How long the sensor takes to read every row, in seconds.
        static let readoutDuration = 0.008

        /// How deep the lamp's pulse is; zero for steady light.
        var flickerDepth = 0.0
        /// The lamp's pulses per second.
        var flickerRate = Double(ScannerMetrics.flickerRate)

        /// Luma for a frame read at `time`, with the scene moved `shift` pixels
        /// and every pixel scaled by `gain`, as auto exposure would.
        func frame(at time: Double, shift: Int = 0, gain: Double = 1, noiseSeed: UInt64) -> [UInt8] {
            var noise = noiseSeed &* 6364136223846793005 &+ 1442695040888963407
            var pixels = [UInt8](repeating: 0, count: Self.width * Self.height)
            for y in 0..<Self.height {
                let rowTime = time + Self.readoutDuration * Double(y) / Double(Self.height)
                let light = 1 + flickerDepth * sin(2 * .pi * flickerRate * rowTime)
                for x in 0..<Self.width {
                    let sceneX = Double(x + shift), sceneY = Double(y + shift)
                    let texture = 120 + 50 * sin(sceneX / 37) * cos(sceneY / 23) + 30 * sin((sceneX + sceneY) / 11)
                    noise = noise &* 6364136223846793005 &+ 1442695040888963407
                    let grain = Double(Int(noise >> 61)) - 3.5
                    pixels[y * Self.width + x] = UInt8(clamping: Int((texture * gain * light + grain).rounded()))
                }
            }
            return pixels
        }
    }

    private func add(_ pixels: [UInt8], at time: Double, to detector: inout FlickerDetector) {
        pixels.withUnsafeBufferPointer { buffer in
            detector.add(
                pixels: buffer.baseAddress!, width: Scene.width, height: Scene.height,
                bytesPerRow: Scene.width, at: time
            )
        }
    }

    /// Feeds frames at `times`, returning the detector afterwards.
    private func run(
        _ scene: Scene, times: [Double], detector: FlickerDetector = FlickerDetector(),
        shift: (Int) -> Int = { _ in 0 }, gain: (Int) -> Double = { _ in 1 }
    ) -> FlickerDetector {
        var detector = detector
        for (index, time) in times.enumerated() {
            add(scene.frame(at: time, shift: shift(index), gain: gain(index), noiseSeed: UInt64(index)), at: time, to: &detector)
        }
        return detector
    }

    private func times(count: Int, framesPerSecond: Double, start: Double = 10) -> [Double] {
        (0..<count).map { start + Double($0) / framesPerSecond }
    }

    @Test("Rolling bands from 100 Hz light are seen", arguments: [60.0, 30.0])
    func detectsFlicker(framesPerSecond: Double) {
        let detector = run(Scene(flickerDepth: 0.15), times: times(count: 20, framesPerSecond: framesPerSecond))
        #expect(detector.isFlickering)
    }

    @Test("Flicker is still seen when the camera drops frames")
    func detectsFlickerAcrossDroppedFrames() {
        let kept = times(count: 30, framesPerSecond: 60).enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
        let detector = run(Scene(flickerDepth: 0.15), times: kept)
        #expect(detector.isFlickering)
    }

    @Test("A steady scene held in a shaking hand isn't flicker")
    func ignoresJitter() {
        let jitter = [0, 3, -2, 4, -3, 1, -4, 2, 0, -1, 3, -3]
        let detector = run(Scene(), times: times(count: 60, framesPerSecond: 60)) { jitter[$0 % jitter.count] }
        #expect(!detector.isFlickering)
    }

    @Test("Panning across a steady scene isn't flicker")
    func ignoresPanning() {
        let detector = run(Scene(), times: times(count: 60, framesPerSecond: 60)) { $0 * 3 }
        #expect(!detector.isFlickering)
    }

    @Test("Auto exposure brightening the whole frame isn't flicker")
    func ignoresExposureRamp() {
        let detector = run(Scene(), times: times(count: 60, framesPerSecond: 60), gain: { 0.7 + Double($0) * 0.01 })
        #expect(!detector.isFlickering)
    }

    /// Looks for the faint half-rate flicker of uneven pulses, as the
    /// analyzer does once exposures last whole pulses.
    private var unevenDetector: FlickerDetector {
        FlickerDetector(rate: ScannerMetrics.unevenFlickerRate, minimumChange: ScannerMetrics.unevenFlickerMinimumChange)
    }

    @Test("Uneven pulses' faint flicker is seen once exposures last a whole pulse")
    func detectsUnevenPulses() {
        // A one-pulse exposure evens out the 100 Hz pulses, leaving only the
        // difference between every other one.
        let scene = Scene(flickerDepth: 0.03, flickerRate: Double(ScannerMetrics.unevenFlickerRate))
        let detector = run(scene, times: times(count: 30, framesPerSecond: 60), detector: unevenDetector)
        #expect(detector.isFlickering)
    }

    @Test("A steady scene held in a shaking hand isn't uneven flicker")
    func unevenIgnoresJitter() {
        let jitter = [0, 3, -2, 4, -3, 1, -4, 2, 0, -1, 3, -3]
        let detector = run(Scene(), times: times(count: 60, framesPerSecond: 60), detector: unevenDetector) {
            jitter[$0 % jitter.count]
        }
        #expect(!detector.isFlickering)
    }

    @Test("Moving at 47 fps, where the frame just before is nearly in phase, isn't uneven flicker")
    func unevenIgnoresMotionAtTwoPulseFrameRate() {
        let detector = run(
            Scene(), times: times(count: 60, framesPerSecond: 47), detector: unevenDetector,
            shift: { $0 * 3 }, gain: { 0.6 + Double($0) * 0.01 }
        )
        #expect(!detector.isFlickering)
    }

    @Test("Reset looks for flicker afresh")
    func resetClearsTheLatch() {
        var detector = run(Scene(flickerDepth: 0.15), times: times(count: 20, framesPerSecond: 60))
        #expect(detector.isFlickering)
        detector.reset()
        #expect(!detector.isFlickering)
    }
}
