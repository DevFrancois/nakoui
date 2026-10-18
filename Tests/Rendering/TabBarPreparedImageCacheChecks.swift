import CoreGraphics
import Foundation

nonisolated private final class PreparationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ObjectIdentifier] = []
    let gate = DispatchSemaphore(value: 0)

    func record(_ image: CGImage) {
        precondition(!Thread.isMainThread, "image preparation ran on the main thread")
        lock.lock(); calls.append(ObjectIdentifier(image)); lock.unlock()
    }
    var order: [ObjectIdentifier] {
        lock.lock(); defer { lock.unlock() }; return calls
    }
    func prepare(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage? {
        record(image)
        precondition(gate.wait(timeout: .now() + 10) == .success, "test did not release worker")
        return TabBarPreparedImageCache.prepareImage(image, width, height)
    }
}

@main
struct PreparedImageChecks {
    @MainActor static func main() async {
        func source(_ value: CGFloat, size: Int = 8) -> CGImage {
            let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: value, green: 0.5, blue: 1 - value, alpha: 0.75))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            return context.makeImage()!
        }
        func eventually(_ message: String, _ condition: @MainActor () -> Bool) async {
            for _ in 0..<1000 {
                if condition() { return }
                try! await Task.sleep(for: .milliseconds(2))
            }
            preconditionFailure(message)
        }
        func isReady(_ result: TabBarPreparedImageCache.Result) -> Bool {
            if case .ready = result { return true }; return false
        }
        func isPending(_ result: TabBarPreparedImageCache.Result) -> Bool {
            if case .pending = result { return true }; return false
        }
        func isUnavailable(_ result: TabBarPreparedImageCache.Result) -> Bool {
            if case .unavailable = result { return true }; return false
        }
        let a = source(0.1), b = source(0.3), c = source(0.6), d = source(0.9)
        let probe = PreparationProbe()
        let cache = TabBarPreparedImageCache(limits: .init(entries: 4, rasterBytes: 4096, pendingJobs: 3), prepare: { probe.prepare($0, $1, $2) })
        precondition(isPending(cache.image(for: a, priority: .prewarm)))
        await eventually("first worker did not start") { probe.order.count == 1 }
        cache.image(for: b, priority: .prewarm)
        cache.image(for: c, priority: .prewarm)
        for _ in 0..<100 { precondition(isPending(cache.image(for: a))) }
        precondition(cache.statistics.startedJobs == 1, "pending requests must deduplicate")
        precondition(cache.statistics.pendingJobs == 3)
        cache.image(for: d) // A visible miss replaces the oldest queued prewarm.
        precondition(cache.statistics.pendingJobs == 3)
        precondition(cache.statistics.entries == 3)
        probe.gate.signal()
        await eventually("visible work did not start next") { probe.order.count == 2 }
        precondition(probe.order == [ObjectIdentifier(a), ObjectIdentifier(d)])
        precondition(isReady(cache.image(for: a)))
        probe.gate.signal()
        await eventually("remaining prewarm did not start") { probe.order.count == 3 }
        precondition(probe.order.last == ObjectIdentifier(c))
        probe.gate.signal()
        await eventually("queue did not drain") { cache.statistics.pendingJobs == 0 }
        precondition(isReady(cache.image(for: d)))
        precondition(cache.statistics.startedJobs == 3, "evicted queued source must never run")
        print("PASS off-main serial work, nonblocking misses, deduplication and visible priority")

        let failureProbe = PreparationProbe()
        let failedKey = ObjectIdentifier(a)
        let failureCache = TabBarPreparedImageCache(limits: .init(entries: 1, rasterBytes: 1024, pendingJobs: 1)) { image, width, height in
            failureProbe.record(image)
            return ObjectIdentifier(image) == failedKey ? nil : TabBarPreparedImageCache.prepareImage(image, width, height)
        }
        failureCache.image(for: a)
        await eventually("failed request did not settle") { failureCache.statistics.pendingJobs == 0 }
        for _ in 0..<100 { precondition(isUnavailable(failureCache.image(for: a))) }
        precondition(failureCache.statistics.startedJobs == 1, "failure spun new work")
        failureCache.image(for: b)
        await eventually("replacement did not prepare") { isReady(failureCache.image(for: b)) }
        failureCache.image(for: a)
        await eventually("evicted failure was not retryable") { failureCache.statistics.pendingJobs == 0 }
        precondition(failureCache.statistics.startedJobs == 3)
        print("PASS failed-entry stability, bounded eviction and retry after eviction")

        let purgeProbe = PreparationProbe()
        let purgeCache = TabBarPreparedImageCache(limits: .init(entries: 2, rasterBytes: 1024, pendingJobs: 2), prepare: { purgeProbe.prepare($0, $1, $2) })
        purgeCache.image(for: a); purgeCache.image(for: b, priority: .prewarm)
        await eventually("purge worker did not start") { purgeProbe.order.count == 1 }
        precondition(purgeCache.statistics.rasterBytes == 1024)
        purgeCache.removeAll()
        precondition(purgeCache.statistics.rasterBytes == 512, "running memory reservation was dropped early")
        precondition(purgeCache.statistics.entries == 1 && purgeCache.statistics.pendingJobs == 1)
        purgeCache.image(for: c)
        precondition(purgeCache.statistics.rasterBytes <= 1024)
        purgeProbe.gate.signal()
        await eventually("post-purge replacement did not start") { purgeProbe.order.count == 2 }
        precondition(purgeProbe.order == [ObjectIdentifier(a), ObjectIdentifier(c)])
        precondition(purgeCache.statistics.entries == 1, "discarded completion repopulated cache")
        purgeProbe.gate.signal()
        await eventually("replacement did not settle") { isReady(purgeCache.image(for: c)) }
        purgeCache.image(for: a)
        await eventually("purged identity did not get a new generation") { purgeProbe.order.count == 3 }
        precondition(purgeCache.statistics.rasterBytes <= 1024)
        purgeProbe.gate.signal()
        await eventually("new generation did not settle") { isReady(purgeCache.image(for: a)) }
        print("PASS pending purge, completion generation safety and in-flight memory accounting")

        let rejectCache = TabBarPreparedImageCache(limits: .init(entries: 2, rasterBytes: 511, pendingJobs: 1)) { _, _, _ in
            preconditionFailure("over-budget image must not reach decoder")
        }
        precondition(isUnavailable(rejectCache.image(for: a)))
        precondition(rejectCache.statistics.entries == 0 && rejectCache.statistics.startedJobs == 0)
        precondition(rejectCache.statistics.rasterBytes == 0)
        print("PASS over-budget admission never decodes synchronously or starts work")
    }
}
