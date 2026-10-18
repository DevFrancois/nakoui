import CoreVideo
import Metal
import UIKit
#if DEBUG
import ImageIO
import UniformTypeIdentifiers
#endif

/// Captures ordinary UIKit/SwiftUI colors directly into Metal-readable storage.
/// Layer rendering still runs on the main thread; the caller measures that cost
/// and schedules captures independently from the GPU's presentation cadence.
@MainActor
final class TabBarUITextureCapture {
    @MainActor
    final class Frame {
        let texture: MTLTexture
        let rectInWindow: CGRect
        let captureTime: CFTimeInterval
        fileprivate let buffer: Buffer

        fileprivate init(buffer: Buffer, rect: CGRect, time: CFTimeInterval) {
            self.buffer = buffer
            texture = buffer.texture
            rectInWindow = rect
            captureTime = time
        }

        /// Lease before encoding a read; release on the main actor after the
        /// command buffer completes. Keeping the MTLTexture alone is insufficient
        /// because the capture pool otherwise could overwrite its IOSurface.
        func retainGPURead() { buffer.gpuReaders += 1 }

        func releaseGPURead() {
            precondition(buffer.gpuReaders > 0, "Unbalanced UI reflection texture lease")
            buffer.gpuReaders -= 1
        }
    }

    @MainActor
    fileprivate final class Buffer {
        let pixelBuffer: CVPixelBuffer
        // Core Video requires this wrapper to outlive all GPU use of its texture.
        let metalTexture: CVMetalTexture
        let texture: MTLTexture
        let context: CGContext
        let width: Int
        let height: Int
        var gpuReaders = 0

        init?(width: Int, height: Int, cache: CVMetalTextureCache) {
            let attributes: [CFString: Any] = [
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
            ]
            var image: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      kCVPixelFormatType_32BGRA,
                                      attributes as CFDictionary, &image) == kCVReturnSuccess,
                  let image else { return nil }
            var wrapper: CVMetalTexture?
            let textureAttributes = [kCVMetalTextureUsage: MTLTextureUsage.shaderRead.rawValue]
            guard CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, image, textureAttributes as CFDictionary,
                .bgra8Unorm, width, height, 0, &wrapper
            ) == kCVReturnSuccess, let wrapper,
                  let texture = CVMetalTextureGetTexture(wrapper),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess else { return nil }
            defer { CVPixelBufferUnlockBaseAddress(image, []) }
            guard let address = CVPixelBufferGetBaseAddress(image),
                  let context = CGContext(
                    data: address, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(image), space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                        CGImageAlphaInfo.premultipliedFirst.rawValue
                  ) else { return nil }
            pixelBuffer = image
            metalTexture = wrapper
            self.texture = texture
            self.context = context
            self.width = width
            self.height = height
            texture.label = "Tab bar nearby UI colors (shared IOSurface)"
        }
    }

    private(set) var current: Frame?
    private(set) var previous: Frame?
    private(set) var lastCaptureDuration: CFTimeInterval = 0
    private(set) var lastCaptureWasComplete = true
    /// False when the latest capture reproduced `current` exactly.
    private(set) var lastCaptureChanged = true

    private let textureCache: CVMetalTextureCache
    private let layerRenderer = TabBarLayerRegionRenderer()
    // Two frames support interpolation, with two spare surfaces for GPU readers.
    // Allocation and CPU writes never wait for an in-flight GPU read to finish.
    private var buffers: [Buffer?] = Array(repeating: nil, count: 4)
    // This is a broad color field, not readable reflected text. Keep the
    // optical contour at drawable resolution while sampling nearby UI coarsely.
    private static let maximumTextureDimension: CGFloat = 160
    #if DEBUG
    private let usesHierarchyCapture = ProcessInfo.processInfo.environment["TABBAR_HIERARCHY_CAPTURE"] == "1"
    private let dumpsCapture = ProcessInfo.processInfo.environment["TABBAR_DUMP_CAPTURE"] == "1"
    private let captureDumpNotBefore: CFTimeInterval = {
        guard let value = ProcessInfo.processInfo.environment["TABBAR_DUMP_CAPTURE_DELAY"],
              let delay = Double(value), delay.isFinite else { return 0 }
        return CACurrentMediaTime() + max(0, delay)
    }()
    private var hasDumpedCapture = false
    private var lastStageLogTime: CFTimeInterval = 0
    #endif

    init?(device: MTLDevice) {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
                == kCVReturnSuccess, let cache else { return nil }
        textureCache = cache
    }

    /// `rect` is the region around the capsule that its rim can sample. The
    /// capsule plus a six-point guard is clipped out without hiding any views.
    /// The returned texture's row zero is the top of `rectInWindow`.
    ///
    /// Metal/video layers may not appear in a UIKit hierarchy capture; their
    /// producer supplies those pixels separately through the direct texture API.
    @discardableResult
    func capture(window: UIWindow, rect: CGRect, excluding: CGRect,
                 at time: CFTimeInterval) -> Bool {
        guard time.isFinite, rect.hasFiniteArea, window.bounds.hasFiniteArea else { return false }
        let clippedRect = rect.intersection(window.bounds)
        guard clippedRect.hasFiniteArea else { return false }
        // Stable point-aligned bounds avoid changing the sampled region by tiny
        // subpixel amounts while the tab bar settles after a layout update.
        let captureRect = clippedRect.integral.intersection(window.bounds)
        let scale = min(1, Self.maximumTextureDimension / max(captureRect.width, captureRect.height))
        let width = max(1, Int(ceil(captureRect.width * scale)))
        let height = max(1, Int(ceil(captureRect.height * scale)))
        guard let index = buffers.firstIndex(where: { candidate in
            guard let candidate else { return true }
            return candidate.gpuReaders == 0 &&
                candidate !== current?.buffer && candidate !== previous?.buffer
        }) else { return false }

        let started = CACurrentMediaTime()
        var capturedCost: CFTimeInterval?
        defer { lastCaptureDuration = capturedCost ?? (CACurrentMediaTime() - started) }
        if buffers[index]?.width != width || buffers[index]?.height != height {
            buffers[index] = Buffer(width: width, height: height, cache: textureCache)
            // Drop cached wrappers from obsolete sizes during live resizing.
            // Explicitly retained wrappers remain valid, including GPU leases.
            CVMetalTextureCacheFlush(textureCache, 0)
        }
        let allocated = CACurrentMediaTime()
        guard let buffer = buffers[index],
              CVPixelBufferLockBaseAddress(buffer.pixelBuffer, []) == kCVReturnSuccess else { return false }
        let locked = CACurrentMediaTime()
        let context = buffer.context
        context.saveGState()
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / captureRect.width,
                        y: -CGFloat(height) / captureRect.height)
        context.translateBy(x: -captureRect.minX, y: -captureRect.minY)
        let clip = CGMutablePath()
        clip.addRect(captureRect)
        if excluding.hasFiniteArea {
            let excluded = excluding.insetBy(dx: -6, dy: -6).intersection(captureRect)
            if excluded.hasFiniteArea { clip.addRect(excluded) }
        }
        context.addPath(clip)
        context.clip(using: .evenOdd)
        UIGraphicsPushContext(context)
        let drawingStarted = CACurrentMediaTime()
        window.traitCollection.performAsCurrent {
            #if DEBUG
            if usesHierarchyCapture {
                lastCaptureWasComplete = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            } else {
                renderLayers(of: window, rect: captureRect, excluding: excluding, into: context)
            }
            #else
            renderLayers(of: window, rect: captureRect, excluding: excluding, into: context)
            #endif
        }
        let drawn = CACurrentMediaTime()
        UIGraphicsPopContext()
        context.restoreGState()
        context.flush()
        lastCaptureChanged = !matchesCurrent(buffer, rect: captureRect)
        CVPixelBufferUnlockBaseAddress(buffer.pixelBuffer, [])
        let flushed = CACurrentMediaTime()

        // An identical capture keeps the existing frames, so nothing needs to
        // be decoded or redrawn. An incomplete UIKit snapshot can still contain
        // useful ordinary UI; direct GPU producers supply layers UIKit cannot capture.
        if lastCaptureChanged {
            previous = current?.rectInWindow == captureRect ? current : nil
            current = Frame(buffer: buffer, rect: captureRect, time: time)
        }
        capturedCost = CACurrentMediaTime() - started
        #if DEBUG
        if dumpsCapture, flushed - lastStageLogTime >= 2 {
            lastStageLogTime = flushed
            NSLog("TabBarCapture stages mode=%@ alloc=%.3fms lock=%.3fms setup=%.3fms draw=%.3fms flush=%.3fms total=%.3fms rendered=%ld skipped=%ld",
                  usesHierarchyCapture ? "hierarchy" : "layers",
                  (allocated - started) * 1000, (locked - allocated) * 1000,
                  (drawingStarted - locked) * 1000, (drawn - drawingStarted) * 1000,
                  (flushed - drawn) * 1000, (capturedCost ?? 0) * 1000,
                  layerRenderer.renderedSubtrees, layerRenderer.skippedSubtrees)
        }
        if dumpsCapture, !hasDumpedCapture, flushed >= captureDumpNotBefore {
            hasDumpedCapture = true
            dumpCapture(buffer)
            dumpLayers(of: window, captureRect: captureRect)
        }
        #endif
        return true
    }

    func reset() {
        current = nil
        previous = nil
        lastCaptureDuration = 0
        lastCaptureWasComplete = true
        lastCaptureChanged = true
        // Outstanding Frame leases retain their Core Video wrappers. Keep the
        // bounded pool allocated, but never write a leased slot after reset.
    }

    /// `buffer` must be locked. Compares its pixels with the current frame's.
    private func matchesCurrent(_ buffer: Buffer, rect: CGRect) -> Bool {
        guard let other = current?.buffer, current?.rectInWindow == rect, other !== buffer,
              other.width == buffer.width, other.height == buffer.height,
              CVPixelBufferLockBaseAddress(other.pixelBuffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(other.pixelBuffer, .readOnly) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer.pixelBuffer)
        guard rowBytes == CVPixelBufferGetBytesPerRow(other.pixelBuffer),
              let lhs = CVPixelBufferGetBaseAddress(buffer.pixelBuffer),
              let rhs = CVPixelBufferGetBaseAddress(other.pixelBuffer) else { return false }
        return memcmp(lhs, rhs, rowBytes * buffer.height) == 0
    }

    private func renderLayers(of window: UIWindow, rect: CGRect, excluding: CGRect, into context: CGContext) {
        // Sample the layer tree's actual image contents. The presentation tree
        // follows in-flight geometry animations without a render-server window
        // snapshot. Metal/video surfaces are supplied through their direct feed.
        // Core Animation does not promise every effect is renderable here; keep
        // the hierarchy path available for fidelity comparisons on device.
        layerRenderer.render(window: window, rect: rect, excluding: excluding.insetBy(dx: -6, dy: -6), in: context)
        lastCaptureWasComplete = true
    }

    #if DEBUG
    private func dumpLayers(of window: UIWindow, captureRect: CGRect) {
        var lines = ["TabBarCapture layer tree ROI=\(captureRect) traits=\(window.traitCollection.userInterfaceStyle.rawValue)"]
        var count = 0
        func walk(_ layer: CALayer, depth: Int) {
            guard count < 2400, depth < 40 else { return }
            count += 1
            let rect = layer.convert(layer.bounds, to: window.layer)
            let shownLayer = layer.presentation() ?? layer
            let shownRoot = window.layer.presentation() ?? window.layer
            let shownRect = shownLayer.convert(shownLayer.bounds, to: shownRoot)
            let contentsType = layer.contents.map { String(describing: type(of: $0)) } ?? "nil"
            let ownerType = layer.delegate.map { String(describing: type(of: $0)) } ?? "nil"
            let maskType = layer.mask.map { String(describing: type(of: $0)) } ?? "nil"
            lines.append("\(String(repeating: " ", count: depth))\(count) \(type(of: layer)) owner=\(ownerType) rect=\(rect) shown=\(shownRect) near=\(shownRect.intersects(captureRect)) hidden=\(layer.isHidden) opacity=\(layer.opacity) contents=\(contentsType) clips=\(layer.masksToBounds) radius=\(layer.cornerRadius) curve=\(layer.cornerCurve.rawValue) mask=\(maskType) raster=\(layer.shouldRasterize) children=\(layer.sublayers?.count ?? 0)")
            for child in layer.sublayers ?? [] { walk(child, depth: depth + 1) }
        }
        walk(window.layer, depth: 0)
        lines.append("TabBarCapture layer count=\(count)")
        let result = lines.joined(separator: "\n")
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? result.write(to: directory.appendingPathComponent("TabBarLayers.txt"), atomically: true, encoding: .utf8)
        }
        for line in lines { NSLog("%@", line) }
    }

    private func dumpCapture(_ buffer: Buffer) {
        guard CVPixelBufferLockBaseAddress(buffer.pixelBuffer, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(buffer.pixelBuffer, .readOnly) }
        guard let image = buffer.context.makeImage(),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent("TabBarCapture.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) {
            NSLog("Tab bar capture comparison saved to %@", url.path)
        }
    }
    #endif
}
