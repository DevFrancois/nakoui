import MetalKit
import SwiftUI
import UIKit

@MainActor
protocol TabBarReflectionConsumer: AnyObject {
    func uiDidMove()
    func receive(texture: MTLTexture, commandBuffer: MTLCommandBuffer, from view: UIView)
    func clearReflection(from view: UIView?)
}

/// One connection per navigation root/window. Frames go straight to the native
/// renderer; publishing a video frame never invalidates the SwiftUI view tree.
@MainActor
final class TabBarReflectionSource {
    private weak var consumer: (any TabBarReflectionConsumer)?
    private weak var producerView: MTKView?
    private var frameRequested = false

    /// Existing scroll geometry callbacks notify the native receiver without
    /// publishing state or invalidating the SwiftUI tree.
    func uiDidMove() {
        consumer?.uiDidMove()
    }

    /// Pass this method to CardCarousel.onRenderTexture when placing Carousel.
    /// The consumer appends its optical pass to Carousel's current submission.
    func render(texture: MTLTexture, commandBuffer: MTLCommandBuffer, view: UIView) {
        producerView = view as? MTKView
        consumer?.receive(texture: texture, commandBuffer: commandBuffer, from: view)
    }

    /// Pass this method to CardCarousel.onRenderTexture's onUnavailable callback.
    func remove(view: UIView) {
        if producerView === view { producerView = nil }
        consumer?.clearReflection(from: view)
    }

    func clear() {
        producerView = nil
        consumer?.clearReflection(from: nil)
    }

    /// A settled Carousel pauses its clock. Request one fresh GPU frame after
    /// receiver layout/appearance changes, or when its final frame was skipped.
    /// Coalescing also avoids re-entering the producer while it is encoding.
    func requestFrame() {
        guard !frameRequested, producerView != nil, consumer != nil else { return }
        frameRequested = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameRequested = false
            guard self.consumer != nil else { return }
            self.producerView?.draw()
        }
    }

    func connect(_ consumer: any TabBarReflectionConsumer) {
        guard self.consumer !== consumer else { return }
        self.consumer?.clearReflection(from: nil)
        self.consumer = consumer
    }

    func disconnect(_ consumer: any TabBarReflectionConsumer) {
        if self.consumer === consumer { self.consumer = nil }
    }
}

extension EnvironmentValues {
    @Entry var tabBarReflectionSource: TabBarReflectionSource? = nil
}
