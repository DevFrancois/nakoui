import CoreGraphics
import Foundation

/// Prepares immutable photo pixels away from UIKit's capture/display callbacks.
/// Ownership, admission and lookup stay on the main actor; one serial worker
/// owns each temporary bitmap context. No caller waits for a pending result.
@MainActor
final class TabBarPreparedImageCache {
    static let shared = TabBarPreparedImageCache()

    enum Result {
        case ready(CGImage)
        case pending
        case unavailable
        case unsupported
    }
    enum Priority { case visible, prewarm }
    nonisolated struct Limits {
        var entries = 16
        var rasterBytes = 32 * 1024 * 1024
        var pendingJobs = 8
    }
    struct Statistics {
        let entries: Int
        let pendingJobs: Int
        let rasterBytes: Int
        let startedJobs: Int
    }
    private enum State {
        case queued, running, ready(CGImage), failed
    }
    private final class Entry {
        let source: CGImage
        let width: Int
        let height: Int
        let rasterBytes: Int
        let generation: UInt64
        var priority: Priority
        var state = State.queued
        var lastUse: UInt64
        var discardOnCompletion = false

        init(source: CGImage, width: Int, height: Int, rasterBytes: Int,
             generation: UInt64, priority: Priority, lastUse: UInt64) {
            self.source = source; self.width = width; self.height = height
            self.rasterBytes = rasterBytes; self.generation = generation
            self.priority = priority; self.lastUse = lastUse
        }
    }
    // CGImages are immutable. Only the image and scalar values cross to the
    // worker; UIKit, CALayers, entries and bitmap contexts never cross actors.
    nonisolated private struct Job: @unchecked Sendable {
        let source: CGImage
        let width: Int
        let height: Int
        let generation: UInt64
        let visible: Bool
    }
    typealias Prepare = @Sendable (CGImage, Int, Int) -> CGImage?
    private let worker = DispatchQueue(label: "tab-bar.prepare-image", qos: .userInitiated)
    private let prepare: Prepare
    private let limits: Limits
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var queue: [ObjectIdentifier] = []
    private var running: ObjectIdentifier?
    private var rasterBytes = 0
    private var generation: UInt64 = 0
    private var use: UInt64 = 0
    private var startedJobs = 0

    init(limits: Limits = Limits(), prepare: @escaping Prepare = { TabBarPreparedImageCache.prepareImage($0, $1, $2) }) {
        self.limits = limits
        self.prepare = prepare
    }

    var statistics: Statistics {
        Statistics(entries: entries.count, pendingJobs: queue.count + (running == nil ? 0 : 1),
                   rasterBytes: rasterBytes, startedJobs: startedJobs)
    }

    @discardableResult
    func image(for source: CGImage, priority: Priority = .visible) -> Result {
        let key = ObjectIdentifier(source)
        use &+= 1
        if let entry = entries[key] {
            entry.lastUse = use
            switch entry.state {
            case .ready(let image): return .ready(image)
            case .failed: return .unavailable
            case .running: return .pending
            case .queued:
                if priority == .visible, entry.priority == .prewarm {
                    entry.priority = .visible
                    queue.removeAll { $0 == key }
                    queue.insert(key, at: 0)
                }
                return .pending
            }
        }
        guard !source.isMask, source.alphaInfo != .alphaOnly,
              let size = Self.preparedSize(source) else { return .unsupported }
        let (sourceBytes, overflow) = source.bytesPerRow.multipliedReportingOverflow(by: source.height)
        let outputBytes = size.width * size.height * 4
        guard !overflow, sourceBytes <= limits.rasterBytes - outputBytes,
              limits.entries > 0, limits.pendingJobs > 0 else { return .unavailable }
        let cost = sourceBytes + outputBytes
        while entries.count >= limits.entries || rasterBytes + cost > limits.rasterBytes ||
                queue.count + (running == nil ? 0 : 1) >= limits.pendingJobs {
            let pendingFull = queue.count + (running == nil ? 0 : 1) >= limits.pendingJobs
            let candidates = entries.filter { key, entry in
                guard key != running else { return false }
                if pendingFull {
                    guard case .queued = entry.state else { return false }
                    return priority == .visible && entry.priority == .prewarm
                }
                if case .queued = entry.state, priority == .prewarm,
                   entry.priority == .visible { return false }
                return true
            }
            guard let oldest = candidates.min(by: { $0.value.lastUse < $1.value.lastUse }) else { return .unavailable }
            remove(oldest.key)
        }
        generation &+= 1
        let entry = Entry(source: source, width: size.width, height: size.height,
                          rasterBytes: cost, generation: generation, priority: priority, lastUse: use)
        entries[key] = entry
        rasterBytes += cost
        if priority == .visible { queue.insert(key, at: 0) } else { queue.append(key) }
        startNext()
        return .pending
    }

    /// In-flight reservations remain counted until their worker finishes. A
    /// purged completion cannot repopulate the cache or overwrite a newer image.
    func removeAll() {
        for key in Array(entries.keys) {
            if key == running { entries[key]?.discardOnCompletion = true }
            else { remove(key) }
        }
    }

    private func remove(_ key: ObjectIdentifier) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        rasterBytes -= entry.rasterBytes
        queue.removeAll { $0 == key }
    }

    private func startNext() {
        guard running == nil, !queue.isEmpty else { return }
        let key = queue.removeFirst()
        guard let entry = entries[key] else { startNext(); return }
        running = key
        entry.state = .running
        startedJobs += 1
        let job = Job(source: entry.source, width: entry.width, height: entry.height,
                      generation: entry.generation, visible: entry.priority == .visible)
        let prepare = prepare
        worker.async { [weak self] in
            let preparedOnMainThread = Thread.isMainThread
            let started = CFAbsoluteTimeGetCurrent()
            let image = autoreleasepool { prepare(job.source, job.width, job.height) }
            let duration = CFAbsoluteTimeGetCurrent() - started
            DispatchQueue.main.async { [weak self] in
                self?.complete(job, image: image, duration: duration, preparedOnMainThread: preparedOnMainThread)
            }
        }
    }

    private func complete(_ job: Job, image: CGImage?, duration: TimeInterval, preparedOnMainThread: Bool) {
        let key = ObjectIdentifier(job.source)
        guard running == key, let entry = entries[key], entry.generation == job.generation else { return }
        running = nil
        if entry.discardOnCompletion { remove(key) }
        else { entry.state = image.map(State.ready) ?? .failed }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TABBAR_DUMP_CAPTURE"] == "1" {
            NSLog("TabBarCapture image prepared asynchronously %ldx%ld -> %ldx%ld %.3fms cached=%ld rasterBytes=%ld success=%d origin=%@ workerMain=%d",
                  job.source.width, job.source.height, job.width, job.height, duration * 1000,
                  entries.count, rasterBytes, image != nil ? 1 : 0,
                  job.visible ? "visible" : "prewarm", preparedOnMainThread ? 1 : 0)
        }
        #endif
        startNext()
    }

    nonisolated private static func preparedSize(_ source: CGImage) -> (width: Int, height: Int)? {
        // Exact aspect keeps CALayer's native aspect-fit/fill mapping unchanged.
        var divisor = source.width
        var remainder = source.height
        while remainder != 0 {
            let next = divisor % remainder; divisor = remainder; remainder = next
        }
        guard divisor > 0 else { return nil }
        let unitWidth = source.width / divisor
        let unitHeight = source.height / divisor
        let units = min(divisor, 256 / max(unitWidth, unitHeight))
        if units > 0 { return (unitWidth * units, unitHeight * units) }
        // No exact reduction fits, as with coprime sides. Rounding to 256 on the
        // long side changes the aspect by under half a pixel in 256.
        guard source.width > 0, source.height > 0 else { return nil }
        let scale = 256 / Double(max(source.width, source.height))
        return (max(1, Int((Double(source.width) * scale).rounded())),
                max(1, Int((Double(source.height) * scale).rounded())))
    }

    nonisolated static func prepareImage(_ source: CGImage, _ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                        CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        bitmap.interpolationQuality = .high
        bitmap.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.makeImage()
    }
}
