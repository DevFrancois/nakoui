import Foundation
import Synchronization
import Testing
@testable import XStyle_TabBar

/// The tab bar uses Carousel's existing worker handoff. Exercise delayed driver
/// and scheduling responses without depending on a particular GPU or display.
@MainActor
struct TabBarDrawableBrokerTests {
    @Test("A blocked drawable leaves UI work free and pending requests bounded")
    func blockedAcquisition() async {
        let broker = CarouselDrawableBroker<Int>()
        let gate = DispatchSemaphore(value: 0)
        let started = Mutex(false)
        defer { gate.signal() }
        var prepared: [Int] = []
        var consumed: [Int] = []
        var latestUIState = 0
        var encodedUIStates: [Int] = []
        broker.request(prepare: {
            prepared.append(1)
            return {
                #expect(!Thread.isMainThread)
                started.withLock { $0 = true }
                #expect(gate.wait(timeout: .now() + 3) == .success)
                return 1
            }
        }, consume: { value, finish in
            consumed.append(value)
            encodedUIStates.append(latestUIState)
            finish()
        })
        #expect(await waitUntil { started.withLock { $0 } })
        // These model input/layout changes while the driver is blocked.
        for value in 2...20 {
            latestUIState = value
            broker.request(prepare: {
                prepared.append(value)
                return { value }
            }, consume: { value, finish in
                consumed.append(value)
                encodedUIStates.append(latestUIState)
                finish()
            })
        }
        #expect(prepared == [1])
        #expect(broker.isBusy && broker.hasPendingRequest)
        gate.signal()
        #expect(await waitUntil { consumed.count == 2 })
        #expect(prepared == [1, 20])
        #expect(consumed == [1, 20])
        #expect(encodedUIStates == [20, 20])
        #expect(!broker.isBusy && !broker.hasPendingRequest)
    }

    @Test("Invalidation discards an old acquisition without pretending it finished")
    func invalidateBlockedAcquisition() async {
        let broker = CarouselDrawableBroker<Int>()
        let gate = DispatchSemaphore(value: 0)
        let started = Mutex(false)
        defer { gate.signal() }
        var consumed: [Int] = []
        broker.request(prepare: {
            return {
                started.withLock { $0 = true }
                #expect(gate.wait(timeout: .now() + 3) == .success)
                return 1
            }
        }, consume: { value, finish in consumed.append(value); finish() })
        #expect(await waitUntil { started.withLock { $0 } })
        broker.request(prepare: { { 2 } }, consume: { value, finish in consumed.append(value); finish() })
        broker.invalidate()
        #expect(broker.isBusy && !broker.hasPendingRequest)
        broker.request(prepare: { { 3 } }, consume: { value, finish in consumed.append(value); finish() })
        gate.signal()
        #expect(await waitUntil { !broker.isBusy })
        #expect(consumed == [3])
    }

    @Test("Delayed scheduling keeps one pending frame and duplicate finish is harmless")
    func delayedScheduling() async {
        let broker = CarouselDrawableBroker<Int>()
        var firstFinish: (() -> Void)?
        var secondFinish: (() -> Void)?
        var consumed: [Int] = []
        broker.request(prepare: { { 1 } }, consume: { value, finish in
            consumed.append(value)
            firstFinish = finish
        })
        #expect(await waitUntil { firstFinish != nil })
        broker.request(prepare: { { 2 } }, consume: { value, finish in
            consumed.append(value)
            secondFinish = finish
        })
        #expect(broker.isBusy && broker.hasPendingRequest)
        #expect(consumed == [1])
        firstFinish?()
        #expect(await waitUntil { secondFinish != nil })
        firstFinish?()
        #expect(broker.isBusy)
        #expect(consumed == [1, 2])
        secondFinish?()
        #expect(!broker.isBusy)
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }
}
