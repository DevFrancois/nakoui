import BarcodeDecoding
import Foundation

/// Spots lights that pulse at a given rate, such as lamps on 50 Hz mains,
/// from the bands they roll through exposures that aren't whole pulses. Such light
/// looks the same in frames a whole number of pulses apart and different in
/// frames half a pulse apart. Steady light gives the opposite, since motion
/// and exposure changes only grow with the time between frames. So each
/// frame's row brightness is compared with an earlier frame of each kind.
nonisolated struct FlickerDetector {
    private struct Profile {
        let time: Double
        /// Log brightness of every sampled row, top to bottom of the sensor.
        let rows: [Float]
    }

    /// Latched once enough frames vote for flicker, until `reset()`: the
    /// exposure that removes the bands also hides them from here.
    private(set) var isFlickering = false
    /// The latest frame's change since out-of-phase and since in-phase
    /// frames, in mean log brightness, for tuning the thresholds.
    private(set) var lastChanges: (pulsing: Float, steady: Float)?
    private let period: Double
    private let minimumChange: Float
    private var history: [Profile] = []
    private var votes: [Bool] = []

    /// - Parameters:
    ///   - rate: Pulses per second to look for.
    ///   - minimumChange: The least mean change in log brightness between
    ///     out-of-phase frames that counts as flicker.
    init(rate: Int = ScannerMetrics.flickerRate, minimumChange: Float = ScannerMetrics.flickerMinimumChange) {
        period = 1 / Double(rate)
        self.minimumChange = minimumChange
    }

    mutating func add(_ image: LumaImage, at time: Double) {
        add(pixels: image.pixels, width: image.width, height: image.height, bytesPerRow: image.bytesPerRow, at: time)
    }

    /// Adds a frame's luma plane, shown at `time` seconds.
    mutating func add(pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, at time: Double) {
        guard !isFlickering, width > 0, height > 0 else { return }
        if let last = history.last, time <= last.time {
            history.removeAll()
        }
        history.removeAll { time - $0.time > ScannerMetrics.flickerHistoryDuration }

        let profile = Profile(
            time: time,
            rows: Self.rowBrightness(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
        )
        if let vote = vote(for: profile) {
            votes.append(vote)
            if votes.count > ScannerMetrics.flickerVoteWindow {
                votes.removeFirst()
            }
            isFlickering = votes.count(where: \.self) >= ScannerMetrics.flickerVotesNeeded
        }
        history.append(profile)
    }

    mutating func reset() {
        isFlickering = false
        forgetFrames()
    }

    /// Drops the frames and votes so far but keeps a latch, such as when
    /// frames stop being comparable for a while.
    mutating func forgetFrames() {
        history.removeAll()
        votes.removeAll()
        lastChanges = nil
    }

    /// Whether `profile` changed much more since the latest frame half a
    /// pulse away than since an older one a whole number of pulses away.
    /// The in-phase frame must be the older, so motion and exposure changes,
    /// which grow with time, only ever count against flicker: at 47 fps the
    /// frame just before is nearly in phase at 50 Hz, and a moving hand read
    /// as flicker. Nil until there is such a pair, such as at frame rates
    /// where there never is.
    private mutating func vote(for profile: Profile) -> Bool? {
        var outOfPhase: Profile?
        var inPhase: Profile?
        for earlier in history.reversed() where earlier.rows.count == profile.rows.count {
            let pulses = (profile.time - earlier.time) / period
            let phase = pulses - pulses.rounded(.down)
            if outOfPhase == nil {
                if abs(phase - 0.5) <= ScannerMetrics.flickerOutOfPhaseTolerance {
                    outOfPhase = earlier
                }
            } else if min(phase, 1 - phase) <= ScannerMetrics.flickerInPhaseTolerance {
                inPhase = earlier
                break
            }
        }
        guard let inPhase, let outOfPhase else { return nil }
        let pulsingChange = Self.change(from: outOfPhase.rows, to: profile.rows)
        let steadyChange = Self.change(from: inPhase.rows, to: profile.rows)
        lastChanges = (pulsingChange, steadyChange)
        return pulsingChange >= minimumChange
            && pulsingChange >= steadyChange * ScannerMetrics.flickerChangeRatio
    }

    /// Mean absolute difference, in log brightness.
    private static func change(from a: [Float], to b: [Float]) -> Float {
        var total: Float = 0
        for index in a.indices {
            total += abs(a[index] - b[index])
        }
        return total / Float(a.count)
    }

    /// The sensor reads rows one after another, so bands run along the
    /// buffer's rows: each sampled row's mean brightness shows them.
    private static func rowBrightness(pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> [Float] {
        let rowStep = ScannerMetrics.flickerRowStep
        let columnStep = ScannerMetrics.flickerColumnStep
        let columns = (width + columnStep - 1) / columnStep
        var rows: [Float] = []
        rows.reserveCapacity((height + rowStep - 1) / rowStep)
        for y in stride(from: 0, to: height, by: rowStep) {
            let row = pixels + y * bytesPerRow
            var sum = 0
            for x in stride(from: 0, to: width, by: columnStep) {
                sum += Int(row[x])
            }
            rows.append(log(Float(sum) / Float(columns) + 1))
        }
        return rows
    }
}
