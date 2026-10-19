import BarcodeDecoding
import Foundation

/// Spots lights that pulse at `ScannerMetrics.flickerRate`, such as lamps on
/// 50 Hz mains, from the bands they roll through short exposures. Such light
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
    private var history: [Profile] = []
    private var votes: [Bool] = []

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
        history.removeAll()
        votes.removeAll()
    }

    /// Whether `profile` changed much more since the latest frame half a
    /// pulse away than since the latest a whole number of pulses away. Nil
    /// until there is one of each, such as at frame rates that never fall
    /// half a pulse apart.
    private func vote(for profile: Profile) -> Bool? {
        let period = 1 / Double(ScannerMetrics.flickerRate)
        var inPhase: Profile?
        var outOfPhase: Profile?
        for earlier in history.reversed() where earlier.rows.count == profile.rows.count {
            let pulses = (profile.time - earlier.time) / period
            let phase = pulses - pulses.rounded(.down)
            if inPhase == nil, min(phase, 1 - phase) <= ScannerMetrics.flickerInPhaseTolerance {
                inPhase = earlier
            } else if outOfPhase == nil, abs(phase - 0.5) <= ScannerMetrics.flickerOutOfPhaseTolerance {
                outOfPhase = earlier
            }
        }
        guard let inPhase, let outOfPhase else { return nil }
        let pulsingChange = Self.change(from: outOfPhase.rows, to: profile.rows)
        let steadyChange = Self.change(from: inPhase.rows, to: profile.rows)
        return pulsingChange >= ScannerMetrics.flickerMinimumChange
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
