import Foundation

/// Main owns requests and handoffs; only acquisition and command submission run
/// on the worker. A busy renderer keeps one replaceable request, never a queue
/// of obsolete animation frames. Resource is generic so blocked drivers can be
/// tested without a Metal device.
final class CarouselDrawableBroker<Resource> {
    typealias Acquire = () -> Resource?
    typealias Prepare = () -> Acquire?
    typealias Consume = (Resource, @escaping () -> Void) -> Void

    private struct Request {
        let prepare: Prepare
        let consume: Consume
    }

    private let worker: DispatchQueue
    private var pending: Request?
    private var activeID: UInt64?
    private var nextID: UInt64 = 0
    private var revision: UInt64 = 0
    var onIdle: (() -> Void)?

    var isBusy: Bool { activeID != nil }
    var hasPendingRequest: Bool { pending != nil }

    init(worker: DispatchQueue = DispatchQueue(label: "carousel.drawable-broker", qos: .userInteractive)) {
        self.worker = worker
    }

    func request(prepare: @escaping Prepare, consume: @escaping Consume) {
        dispatchPrecondition(condition: .onQueue(.main))
        pending = Request(prepare: prepare, consume: consume)
        startIfIdle()
    }

    /// Already acquired/encoded resources remain alive until their owner finishes.
    /// Invalidating a request never pretends that GPU work has completed.
    func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        revision &+= 1
        pending = nil
    }

    func submit(_ work: @escaping () -> Void) {
        worker.async { autoreleasepool(invoking: work) }
    }

    private func startIfIdle() {
        guard activeID == nil, let request = pending else { return }
        pending = nil
        // Layer creation and configuration are permitted only here, on main,
        // before the worker has access to them.
        guard let acquire = request.prepare() else { onIdle?(); return }
        nextID &+= 1
        let id = nextID, generation = revision
        activeID = id
        worker.async { [weak self] in
            let resource = autoreleasepool(invoking: acquire)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.activeID == id, self.revision == generation, let resource else {
                    self.finish(id)
                    return
                }
                request.consume(resource) { [weak self] in self?.finish(id) }
            }
        }
    }

    private func finish(_ id: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeID == id else { return }
        activeID = nil
        if pending != nil { startIfIdle() }
        else { onIdle?() }
    }
}
