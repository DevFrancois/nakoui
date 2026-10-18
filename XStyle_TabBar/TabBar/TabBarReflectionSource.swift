import MetalKit
import SwiftUI
import UIKit

@MainActor
protocol TabBarReflectionConsumer: AnyObject {
    func uiDidMove()
    func receive(texture: MTLTexture, commandBuffer: MTLCommandBuffer, from view: UIView)
    func clearReflection(from view: UIView?)
    func rootLifecycleChanged()
}

/// One connection per navigation root/window. Frames go straight to the native
/// renderer; publishing a video frame never invalidates the SwiftUI view tree.
@MainActor
final class TabBarReflectionSource {
    private weak var consumer: (any TabBarReflectionConsumer)?
    // Navigation notifications must still reach a temporarily disconnected menu.
    private weak var lifecycleConsumer: (any TabBarReflectionConsumer)?
    private weak var producerView: MTKView?
    private var producerUnavailableWhileSuspended = false
    private var frameRequested = false
    private(set) weak var rootView: UIView?
    private(set) var lifecycle = TabBarRootReflectionLifecycle()
    private(set) var contentContext: UInt64 = 0

    func observe(_ consumer: any TabBarReflectionConsumer) {
        lifecycleConsumer = consumer
    }

    func stopObserving(_ consumer: any TabBarReflectionConsumer) {
        if lifecycleConsumer === consumer { lifecycleConsumer = nil }
        disconnect(consumer)
    }

    func setPathIsEmpty(_ value: Bool) {
        guard lifecycle.pathIsEmpty != value else { return }
        lifecycle.setPathIsEmpty(value)
        notifyLifecycle("path")
    }

    @discardableResult
    func rootWillAppear(_ view: UIView) -> UInt64 {
        rootView = view
        let token = lifecycle.willAppear()
        notifyLifecycle("willAppear")
        return token
    }

    func rootDidAppear(generation: UInt64) {
        lifecycle.didAppear(generation: generation)
        notifyLifecycle("didAppear")
    }

    func rootWillDisappear() {
        lifecycle.suspend()
        notifyLifecycle("willDisappear")
    }

    func rootReturnCancelled(generation: UInt64) {
        lifecycle.cancelReturn(generation: generation)
        notifyLifecycle("cancelReturn")
    }

    func rootLayoutChanged() { lifecycleConsumer?.rootLifecycleChanged() }

    private func notifyLifecycle(_ event: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TABBAR_LIFECYCLE"] == "1" {
            print("TABBAR_ROOT time=\(CACurrentMediaTime()) event=\(event) generation=\(lifecycle.generation) phase=\(lifecycle.phase) empty=\(lifecycle.pathIsEmpty) capture=\(lifecycle.canCapture) context=\(contentContext)")
        }
        #endif
        lifecycleConsumer?.rootLifecycleChanged()
    }

    /// Existing scroll geometry callbacks notify the native receiver without
    /// publishing state or invalidating the SwiftUI tree.
    func uiDidMove() {
        consumer?.uiDidMove()
    }

    /// Pass this method to CardCarousel.onRenderTexture when placing Carousel.
    /// The consumer appends its optical pass to Carousel's current submission.
    func render(texture: MTLTexture, commandBuffer: MTLCommandBuffer, view: UIView) {
        producerView = view as? MTKView
        producerUnavailableWhileSuspended = false
        guard lifecycle.canCapture else { return }
        consumer?.receive(texture: texture, commandBuffer: commandBuffer, from: view)
    }

    /// Pass this method to CardCarousel.onRenderTexture's onUnavailable callback.
    func remove(view: UIView) {
        if producerView === view {
            producerView = nil
            producerUnavailableWhileSuspended = consumer == nil
        }
        consumer?.clearReflection(from: view)
    }

    func clear() {
        contentContext &+= 1
        producerView = nil
        producerUnavailableWhileSuspended = false
        // Context changes while covered invalidate retained colors too.
        lifecycleConsumer?.clearReflection(from: nil)
    }

    /// A settled Carousel pauses its clock. Request one fresh GPU frame after
    /// receiver layout/appearance changes, or when its final frame was skipped.
    /// Coalescing also avoids re-entering the producer while it is encoding.
    func requestFrame() {
        guard lifecycle.canCapture, !frameRequested, producerView != nil, consumer != nil else { return }
        let generation = lifecycle.generation
        frameRequested = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameRequested = false
            guard self.consumer != nil, self.lifecycle.canCapture,
                  self.lifecycle.generation == generation else { return }
            self.producerView?.draw()
        }
    }

    func connect(_ consumer: any TabBarReflectionConsumer) {
        guard self.consumer !== consumer else { return }
        self.consumer?.clearReflection(from: nil)
        self.consumer = consumer
        // Keep a temporarily unavailable crop throughout the return transition.
        // Once capture reopens, reconcile a source that did not come back.
        if producerUnavailableWhileSuspended {
            producerUnavailableWhileSuspended = false
            consumer.clearReflection(from: nil)
        }
    }

    func disconnect(_ consumer: any TabBarReflectionConsumer) {
        if self.consumer === consumer { self.consumer = nil }
    }
}

extension EnvironmentValues {
    @Entry var tabBarReflectionSource: TabBarReflectionSource? = nil
}
