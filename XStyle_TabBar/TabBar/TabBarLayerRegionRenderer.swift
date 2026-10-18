import QuartzCore
import UIKit

/// Renders only layer subtrees that can contribute colors near the tab bar.
/// The live tree is never edited. Complex compositing remains with Core Animation;
/// plain layout containers are split so offscreen feed rows are not rasterized.
@MainActor
final class TabBarLayerRegionRenderer {
    private(set) var renderedSubtrees = 0
    private(set) var skippedSubtrees = 0
    #if DEBUG
    private let diagnostics = ProcessInfo.processInfo.environment["TABBAR_DUMP_CAPTURE"] == "1"
    private var lastLogTime: CFTimeInterval = 0
    private var slowRenders: [(duration: CFTimeInterval, detail: String)] = []
    private var loggedImageKinds = Set<String>()
    private var originalRenderDuration: CFTimeInterval = 0
    private var shellRenderDuration: CFTimeInterval = 0
    #endif
    private var excludedRect = CGRect.null
    private struct RoundedClipKey: Hashable {
        var pixelWidth: Int
        var pixelHeight: Int
        var width: CGFloat
        var height: CGFloat
        var radius: CGFloat
        var curve: String
        var corners: UInt
        var flipped: Bool
    }
    private struct RoundedClipEntry {
        var key: RoundedClipKey
        var image: CGImage
        var lastUse: UInt64
    }
    // Immutable native alpha masks only: no captured UI pixels or live layers.
    // Both count and bytes are bounded, including during animated corner changes.
    private var roundedClips: [RoundedClipEntry] = []
    private var roundedClipBytes = 0
    private var clipUse: UInt64 = 0


    private let imageCache: TabBarPreparedImageCache

    init(imageCache: TabBarPreparedImageCache? = nil) {
        self.imageCache = imageCache ?? .shared
    }

    private struct ChildPlacement {
        let layer: CALayer
        let bounds: CGRect
        let localToWindow: CGAffineTransform
        let z: CGFloat
        let index: Int
    }

    func render(window: UIWindow, rect: CGRect, excluding: CGRect, in context: CGContext) {
        renderedSubtrees = 0
        skippedSubtrees = 0
        excludedRect = excluding
        #if DEBUG
        slowRenders.removeAll(keepingCapacity: true)
        originalRenderDuration = 0
        shellRenderDuration = 0
        let frameStarted = CACurrentMediaTime()
        #endif
        let root = window.layer.presentation() ?? window.layer
        #if DEBUG
        let treeAcquired = CACurrentMediaTime()
        #endif
        render(root, bounds: root.bounds, localToWindow: .identity, region: rect.intersection(window.bounds),
               inheritedTraits: window.traitCollection, in: context)
        #if DEBUG
        if diagnostics, CACurrentMediaTime() - lastLogTime >= 2 {
            lastLogTime = CACurrentMediaTime()
            NSLog("TabBarCapture traversal tree=%.3fms originals=%.3fms shells=%.3fms other=%.3fms",
                  (treeAcquired - frameStarted) * 1000, originalRenderDuration * 1000,
                  shellRenderDuration * 1000,
                  (lastLogTime - treeAcquired - originalRenderDuration - shellRenderDuration) * 1000)
            for item in slowRenders.sorted(by: { $0.duration > $1.duration }).prefix(5) {
                NSLog("TabBarCapture slow %.3fms %@", item.duration * 1000, item.detail)
            }
        }
        #endif
    }

    private func render(_ layer: CALayer, bounds: CGRect, localToWindow: CGAffineTransform, region: CGRect,
                        inheritedTraits: UITraitCollection, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0, !region.isEmpty,
              !(layer is CAMetalLayer) else {
            skippedSubtrees += 1
            return
        }
        let boundsInWindow = bounds.applying(localToWindow)
        var visibleRegion = region
        if layer.masksToBounds {
            visibleRegion = visibleRegion.intersection(boundsInWindow)
            guard !visibleRegion.isEmpty else { skippedSubtrees += 1; return }
        }
        let children = layer.sublayers ?? []
        let ownExtent = drawingExtent(of: layer, bounds: bounds, localToWindow: localToWindow)
        let ownImageContributes = contributes(ownExtent, to: visibleRegion)
        // Reject offscreen leaves before crossing the presentation/model bridge
        // or asking SwiftUI's backing layers for contents/delegate/traits. A
        // non-clipping container may still have children outside its own bounds.
        if children.isEmpty, !ownImageContributes {
            skippedSubtrees += 1
            return
        }
        let model = layer.model()
        guard !isTextOrAlphaMask(model, shown: layer) else {
            skippedSubtrees += 1
            return
        }
        let traits = (model.delegate as? UIView)?.traitCollection ?? inheritedTraits
        if children.isEmpty {
            renderOriginal(model, shown: layer, localToWindow: localToWindow, traits: traits, reason: "leaf", in: context)
            return
        }

        var splitReason = reasonNotToSplit(model, shown: layer)
        if layer.masksToBounds, layer.cornerRadius > 0,
           !hasSingleDrawingLeaf(children) {
            // Optimize one image/drawing leaf, including empty UIKit hosting
            // wrappers. Keep overlapping or independently drawn groups native.
            splitReason = "rounded nested group"
        }
        if layer.masksToBounds, layer.cornerRadius > 0,
           localToWindow.b != 0 || localToWindow.c != 0 {
            // A rotated/sheared raster mask would introduce another coverage
            // resampling step. Keep Core Animation's original group for it.
            splitReason = "transformed rounded clip"
        }
        var orderedChildren: [ChildPlacement] = []
        if splitReason == nil {
            if let placements = childPlacements(children, parent: layer, bounds: bounds,
                                                 localToWindow: localToWindow) {
                orderedChildren = placements
            } else {
                splitReason = "3D transform"
            }
        }
        if let reason = splitReason {
            // A non-clipping container can have children outside its own bounds.
            // Conservatively retain its complete subtree instead of dropping
            // overflowing content, masks, group alpha, filters, or 3D transforms.
            guard subtreeContributes(layer, bounds: bounds, localToWindow: localToWindow, region: visibleRegion) else {
                skippedSubtrees += 1
                return
            }
            renderOriginal(model, shown: layer, localToWindow: localToWindow, traits: traits, reason: reason, in: context)
            return
        }

        context.saveGState()
        var beganRoundedGroup = false
        defer {
            if beganRoundedGroup { context.endTransparencyLayer() }
            context.restoreGState()
        }
        if layer.masksToBounds {
            if layer.cornerRadius > 0 {
                guard let mask = roundedClipMask(layer, bounds: bounds, mapping: localToWindow, context: context) else {
                    renderOriginal(model, shown: layer, localToWindow: localToWindow,
                                   traits: traits, reason: "rounded mask allocation", in: context)
                    return
                }
                context.concatenate(localToWindow)
                context.clip(to: bounds, mask: mask)
                context.concatenate(localToWindow.inverted())
                // Apply native rounded coverage once to the composed children,
                // not separately to each overlapping child draw.
                context.beginTransparencyLayer(in: visibleRegion.intersection(boundsInWindow), auxiliaryInfo: nil)
                beganRoundedGroup = true
            } else {
                var mapping = localToWindow
                context.addPath(CGPath(rect: bounds, transform: &mapping))
                context.clip()
            }
        }
        if ownImageContributes, hasOwnImage(layer) {
            renderShell(layer, localToWindow: localToWindow, in: context)
        }
        var childIndex = 0
        while childIndex < orderedChildren.count {
            let child = orderedChildren[childIndex]
            render(child.layer, bounds: child.bounds, localToWindow: child.localToWindow,
                   region: visibleRegion, inheritedTraits: traits, in: context)
            childIndex += 1
        }
    }

    private func hasSingleDrawingLeaf(_ children: [CALayer]) -> Bool {
        guard children.count == 1 else { return false }
        var layer = children[0]
        while true {
            let descendants = layer.sublayers ?? []
            if descendants.isEmpty { return true }
            guard descendants.count == 1, !hasOwnImage(layer) else { return false }
            let model = layer.model()
            guard reasonNotToSplit(model, shown: layer) == nil else { return false }
            layer = descendants[0]
        }
    }

    private func roundedClipMask(_ layer: CALayer, bounds: CGRect,
                                 mapping: CGAffineTransform, context: CGContext) -> CGImage? {
        let pixels = mapping.concatenating(context.ctm)
        let scaleX = hypot(pixels.a, pixels.b)
        let scaleY = hypot(pixels.c, pixels.d)
        guard bounds.width > 0, bounds.height > 0, scaleX.isFinite, scaleY.isFinite,
              scaleX > 0, scaleY > 0 else { return nil }
        let width = max(1, Int(min(512, ceil(bounds.width * scaleX))))
        let height = max(1, Int(min(512, ceil(bounds.height * scaleY))))
        let key = RoundedClipKey(pixelWidth: width, pixelHeight: height,
                                 width: bounds.width, height: bounds.height,
                                 radius: layer.cornerRadius, curve: layer.cornerCurve.rawValue,
                                 corners: layer.maskedCorners.rawValue, flipped: layer.isGeometryFlipped)
        clipUse &+= 1
        var index = 0
        while index < roundedClips.count {
            if roundedClips[index].key == key {
                roundedClips[index].lastUse = clipUse
                return roundedClips[index].image
            }
            index += 1
        }
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width, space: nil,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.alphaOnly.rawValue)) else { return nil }
        bitmap.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        let maskLayer = CALayer()
        maskLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        maskLayer.backgroundColor = CGColor(gray: 1, alpha: 1)
        maskLayer.cornerRadius = layer.cornerRadius
        maskLayer.cornerCurve = layer.cornerCurve
        maskLayer.maskedCorners = layer.maskedCorners
        maskLayer.isGeometryFlipped = layer.isGeometryFlipped
        // CALayer already rounds its own background. Turning on masksToBounds
        // here would multiply the same antialiased edge coverage a second time.
        maskLayer.masksToBounds = false
        maskLayer.render(in: bitmap)
        guard let image = bitmap.makeImage() else { return nil }
        let byteCost = image.bytesPerRow * image.height
        while roundedClips.count >= 16 || roundedClipBytes + byteCost > 512 * 1024 {
            guard let oldest = roundedClips.indices.min(by: { roundedClips[$0].lastUse < roundedClips[$1].lastUse }) else { break }
            let removed = roundedClips.remove(at: oldest).image
            roundedClipBytes -= removed.bytesPerRow * removed.height
        }
        roundedClipBytes += byteCost
        roundedClips.append(RoundedClipEntry(key: key, image: image, lastUse: clipUse))
        return image
    }

    private func childPlacements(_ children: [CALayer], parent: CALayer, bounds: CGRect,
                                 localToWindow: CGAffineTransform) -> [ChildPlacement]? {
        let childrenToWindow = sublayerMapping(of: parent, bounds: bounds).concatenating(localToWindow)
        var placements: [ChildPlacement] = []
        placements.reserveCapacity(children.count)
        var needsSorting = false
        var previousZ = -CGFloat.infinity
        var index = 0
        while index < children.count {
            let child = children[index]
            let transform = child.transform
            guard CATransform3DIsAffine(transform) else { return nil }
            let childBounds = child.bounds
            let z = child.zPosition
            if z < previousZ { needsSorting = true }
            previousZ = z
            let mapping = localToParent(child, bounds: childBounds, transform: transform)
                .concatenating(childrenToWindow)
            placements.append(ChildPlacement(layer: child, bounds: childBounds,
                                             localToWindow: mapping, z: z, index: index))
            index += 1
        }
        // The usual equal-z tree needs no sort or second property scan. Preserve
        // original order at equal z values when sorting a genuinely unordered tree.
        if needsSorting {
            placements.sort { $0.z == $1.z ? $0.index < $1.index : $0.z < $1.z }
        }
        return placements
    }

    private func reasonNotToSplit(_ model: CALayer, shown layer: CALayer) -> String? {
        if layer.opacity != 1 { return "group opacity" }
        if layer.mask != nil { return "mask" }
        if layer.shadowOpacity != 0 { return "group shadow" }
        if layer.borderWidth != 0 { return "border" }
        if layer.masksToBounds, layer.cornerRadius > 0, hasOwnImage(layer) {
            // Splitting a rounded background would apply its edge coverage twice.
            return "rounded background"
        }
        if layer.compositingFilter != nil || !(layer.filters?.isEmpty ?? true) ||
            !(layer.backgroundFilters?.isEmpty ?? true) { return "filters" }
        if !CATransform3DIsAffine(layer.transform) || !CATransform3DIsAffine(layer.sublayerTransform) {
            return "3D transform"
        }
        if type(of: model) == CALayer.self { return nil }
        // Split empty UIView-backed layout containers in this app's hosting
        // hierarchy. Public properties cannot describe arbitrary private drawing,
        // so this is a bounded assumption rather than a general snapshot API;
        // custom drawing containers with their own image keep the original render.
        return model.delegate is UIView && !hasOwnImage(layer) ? nil : "custom drawing container"
    }

    private func contributes(_ extent: CGRect, to region: CGRect) -> Bool {
        let overlap = extent.intersection(region)
        return !overlap.isEmpty && !excludedRect.contains(overlap)
    }

    private func subtreeContributes(_ layer: CALayer, bounds: CGRect, localToWindow: CGAffineTransform, region: CGRect) -> Bool {
        guard !layer.isHidden, layer.opacity > 0, !(layer is CAMetalLayer) else { return false }
        let visible = layer.masksToBounds ? region.intersection(bounds.applying(localToWindow)) : region
        guard !visible.isEmpty else { return false }
        let ownImageContributes = contributes(drawingExtent(of: layer, bounds: bounds, localToWindow: localToWindow), to: visible)
        let children = layer.sublayers ?? []
        if children.isEmpty, !ownImageContributes { return false }
        guard !isTextOrAlphaMask(layer.model(), shown: layer) else { return false }
        if ownImageContributes { return true }
        // The original subtree render owns perspective. Do not approximate its
        // projected extent with an affine box or drop potentially visible pixels.
        guard CATransform3DIsAffine(layer.sublayerTransform) else { return true }
        let childrenToWindow = sublayerMapping(of: layer, bounds: bounds).concatenating(localToWindow)
        var index = 0
        while index < children.count {
            let child = children[index]
            let transform = child.transform
            guard CATransform3DIsAffine(transform) else { return true }
            let childBounds = child.bounds
            let mapping = localToParent(child, bounds: childBounds, transform: transform)
                .concatenating(childrenToWindow)
            if subtreeContributes(child, bounds: childBounds, localToWindow: mapping, region: visible) {
                return true
            }
            index += 1
        }
        return false
    }

    private func isTextOrAlphaMask(_ model: CALayer, shown layer: CALayer) -> Bool {
        if model is CATextLayer || model.delegate is UILabel { return true }
        guard let contents = layer.contents,
              CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return false }
        let image = contents as! CGImage
        #if DEBUG
        if diagnostics, loggedImageKinds.count < 24 {
            let kind = "\(type(of: model)) \(image.width)x\(image.height) bpp=\(image.bitsPerPixel) alpha=\(image.alphaInfo.rawValue) mask=\(image.isMask) colorSpace=\(String(describing: image.colorSpace?.name))"
            if loggedImageKinds.count < 24, loggedImageKinds.insert(kind).inserted {
                NSLog("TabBarCapture image %@", kind)
            }
        }
        #endif
        // Alpha-only glyph/symbol masks have no source RGB. Their compositor tint
        // can differ from a plain layer render, so omit them from this color feed.
        // Photographs and other RGB image content remain eligible.
        return image.isMask || image.alphaInfo == .alphaOnly
    }

    private func hasOwnImage(_ layer: CALayer) -> Bool {
        layer.contents != nil || (layer.backgroundColor?.alpha ?? 0) > 0 ||
            layer.borderWidth > 0 || layer.shadowOpacity > 0
    }

    private func drawingExtent(of layer: CALayer, bounds: CGRect, localToWindow: CGAffineTransform) -> CGRect {
        var local = bounds
        if let shape = layer as? CAShapeLayer, let path = shape.path {
            let stroke = shape.strokeColor == nil ? 0 : max(0, shape.lineWidth) * 0.5 * max(1, shape.miterLimit)
            local = local.union(path.boundingBoxOfPath.insetBy(dx: -stroke, dy: -stroke))
        }
        if layer.shadowOpacity > 0 {
            let shadow = (layer.shadowPath?.boundingBoxOfPath ?? local)
                .offsetBy(dx: layer.shadowOffset.width, dy: layer.shadowOffset.height)
                .insetBy(dx: -layer.shadowRadius * 4, dy: -layer.shadowRadius * 4)
            local = local.union(shadow)
        }
        return local.applying(localToWindow)
    }

    /// Maps bounds coordinates into the parent's untransformed sublayer space.
    /// Passing this mapping down avoids CALayer.convert's repeated ancestor and
    /// presentation/model walks for every bound, clip, extent and draw call.
    private func localToParent(_ layer: CALayer, bounds: CGRect, transform: CATransform3D) -> CGAffineTransform {
        let anchor = layer.anchorPoint
        let position = layer.position
        let origin = CGPoint(x: bounds.minX + anchor.x * bounds.width,
                             y: bounds.minY + anchor.y * bounds.height)
        var mapping = CGAffineTransform.identity
        if layer.isGeometryFlipped {
            mapping = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                        tx: 0, ty: bounds.minY + bounds.maxY)
        }
        return mapping
            .concatenating(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            .concatenating(CATransform3DGetAffineTransform(transform))
            .concatenating(CGAffineTransform(translationX: position.x, y: position.y))
    }

    private func sublayerMapping(of layer: CALayer, bounds: CGRect) -> CGAffineTransform {
        let transform = layer.sublayerTransform
        guard !CATransform3DIsIdentity(transform) else { return .identity }
        let anchor = layer.anchorPoint
        let pivot = CGPoint(x: bounds.minX + anchor.x * bounds.width,
                            y: bounds.minY + anchor.y * bounds.height)
        return CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CATransform3DGetAffineTransform(transform))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
    }

    private func preparedImage(_ model: CALayer, shown layer: CALayer) -> TabBarPreparedImageCache.Result {
        guard type(of: model) == CALayer.self, layer.sublayers?.isEmpty ?? true,
              layer.mask == nil, layer.shadowOpacity == 0, layer.borderWidth == 0,
              layer.cornerRadius == 0, (layer.backgroundColor?.alpha ?? 0) == 0,
              layer.compositingFilter == nil, layer.filters?.isEmpty ?? true,
              layer.backgroundFilters?.isEmpty ?? true,
              layer.minificationFilter == .linear, layer.magnificationFilter == .linear,
              layer.minificationFilterBias == 0,
              layer.contentsRect == CGRect(x: 0, y: 0, width: 1, height: 1),
              layer.contentsCenter == CGRect(x: 0, y: 0, width: 1, height: 1),
              layer.contentsGravity == .resize || layer.contentsGravity == .resizeAspect || layer.contentsGravity == .resizeAspectFill,
              let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return .unsupported }
        if let view = model.delegate as? UIImageView,
           view.image?.renderingMode == .alwaysTemplate || view.image?.isSymbolImage == true { return .unsupported }
        let source = contents as! CGImage
        guard !source.isMask, source.alphaInfo != .alphaOnly else { return .unsupported }
        return imageCache.image(for: source)
    }

    private func renderOriginal(_ model: CALayer, shown layer: CALayer, localToWindow: CGAffineTransform,
                                traits: UITraitCollection, reason: String, in context: CGContext) {
        #if DEBUG
        let start = CACurrentMediaTime()
        #endif
        let prepared = preparedImage(model, shown: layer)
        switch prepared {
        case .pending, .unavailable:
            // Keep capturing current surrounding UI while this immutable photo
            // is prepared. Never decode it here or substitute an older photo.
            skippedSubtrees += 1
            return
        case .ready, .unsupported: break
        }
        context.saveGState()
        context.concatenate(localToWindow)
        traits.performAsCurrent {
            if case .ready(let prepared) = prepared {
                let imageLayer = CALayer()
                imageLayer.bounds = layer.bounds
                imageLayer.contents = prepared
                imageLayer.contentsGravity = layer.contentsGravity
                imageLayer.contentsScale = layer.contentsScale
                imageLayer.contentsRect = layer.contentsRect
                imageLayer.contentsCenter = layer.contentsCenter
                imageLayer.contentsFormat = layer.contentsFormat
                imageLayer.isGeometryFlipped = layer.isGeometryFlipped
                imageLayer.masksToBounds = layer.masksToBounds
                imageLayer.opacity = layer.opacity
                imageLayer.minificationFilter = layer.minificationFilter
                imageLayer.magnificationFilter = layer.magnificationFilter
                imageLayer.minificationFilterBias = layer.minificationFilterBias
                imageLayer.render(in: context)
            } else {
                layer.render(in: context)
            }
        }
        context.restoreGState()
        renderedSubtrees += 1
        #if DEBUG
        if diagnostics {
            originalRenderDuration += CACurrentMediaTime() - start
            let detail = "\(type(of: model)) owner=\(String(describing: model.delegate.map { type(of: $0) })) rect=\(layer.bounds.applying(localToWindow)) children=\(model.sublayers?.count ?? 0) reason=\(reason)"
            let cornerDetail = reason == "rounded clip" ? roundedClipDetails(layer) : ""
            slowRenders.append((CACurrentMediaTime() - start, detail + cornerDetail))
        }
        #endif
    }

    #if DEBUG
    private func roundedClipDetails(_ root: CALayer) -> String {
        var result = " radius=\(root.cornerRadius) curve=\(root.cornerCurve.rawValue) corners=\(root.maskedCorners.rawValue)"
        var layer: CALayer? = root
        var depth = 0
        while let current = layer, depth < 6 {
            var imageDetail = ""
            if let contents = current.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                let image = contents as! CGImage
                imageDetail = " image=\(image.width)x\(image.height) bpp=\(image.bitsPerPixel) space=\(String(describing: image.colorSpace?.name))"
            }
            let children = current.sublayers ?? []
            result += " >\(type(of: current)) bounds=\(current.bounds) clips=\(current.masksToBounds) radius=\(current.cornerRadius) contents=\(String(describing: current.contents.map { type(of: $0) })) children=\(children.count)" + imageDetail
            layer = children.first
            depth += 1
        }
        return result
    }
    #endif

    private func renderShell(_ layer: CALayer, localToWindow: CGAffineTransform, in context: CGContext) {
        #if DEBUG
        let start = CACurrentMediaTime()
        defer { if diagnostics { shellRenderDuration += CACurrentMediaTime() - start } }
        #endif
        // CALayer(layer:) is reserved for Core Animation's presentation copies.
        // A fresh public layer preserves the container's real image and styling.
        let shell = CALayer()
        shell.bounds = layer.bounds
        shell.contents = layer.contents
        shell.contentsRect = layer.contentsRect
        shell.contentsCenter = layer.contentsCenter
        shell.contentsScale = layer.contentsScale
        shell.contentsGravity = layer.contentsGravity
        shell.contentsFormat = layer.contentsFormat
        shell.isGeometryFlipped = layer.isGeometryFlipped
        shell.minificationFilter = layer.minificationFilter
        shell.magnificationFilter = layer.magnificationFilter
        shell.minificationFilterBias = layer.minificationFilterBias
        shell.backgroundColor = layer.backgroundColor
        shell.borderColor = layer.borderColor
        shell.borderWidth = layer.borderWidth
        shell.cornerRadius = layer.cornerRadius
        shell.cornerCurve = layer.cornerCurve
        shell.maskedCorners = layer.maskedCorners
        shell.masksToBounds = layer.masksToBounds
        context.saveGState()
        context.concatenate(localToWindow)
        shell.render(in: context)
        context.restoreGState()
        renderedSubtrees += 1
    }
}
