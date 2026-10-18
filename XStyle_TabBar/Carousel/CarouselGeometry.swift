import CoreGraphics
import Foundation

/// All positions are UIKit points, angles are clockwise radians, velocities are per second.
struct CarouselPose: Equatable {
    var x: Double
    var y: Double
    var height: Double
    var angle: Double = 0
    var promotion: Double = 0
    var opacity: Double = 1
    /// Width over height: the item's own shape, or `layout.cardAspect` (4:5 by default).
    var aspect: Double = 0.8
    /// Turn about the card's vertical axis, radians: past a quarter turn its back shows.
    var turn: Double = 0
    /// Shared scene elevation in points, toward the camera. Resolved only on displayed
    /// frames, so screen-space motion and its velocities remain independent of depth.
    var sceneDepth: Double = 0
    /// A press tilt about the card's own axes, applied after its turn, radians: `tiltX` sends
    /// the bottom edge away, `tiltY` the right edge (the same sense as `turn`). Set only on
    /// frames for a pressed card; motion never carries it.
    var tiltX: Double = 0
    var tiltY: Double = 0
    var isTilted: Bool { tiltX != 0 || tiltY != 0 }
    var width: Double { height * aspect }
    var imageCornerRadius: Double { max(0, width) * 0.034 }

    func outerSize(padding: Double = 0) -> CGSize {
        let padding = padding.isFinite ? max(0, padding) : 8
        return CGSize(width: max(0, width) + 2 * padding, height: max(0, height) + 2 * padding)
    }

    func outerCornerRadius(padding: Double = 0) -> Double {
        let padding = padding.isFinite ? max(0, padding) : 8
        let size = outerSize(padding: padding)
        return min(Double(min(size.width, size.height)) / 2, imageCornerRadius + padding)
    }
}

struct CarouselRenderedCard: Equatable {
    var index: Int
    var pose: CarouselPose
    var occluderIndices: [Int] = []
    var occlusion: Double = 0
}

struct CarouselFrame {
    var size: CGSize
    var wheel: [CarouselRenderedCard]
    var promoted: [CarouselRenderedCard]
    var scrimOpacity: Double
    var position: Double = 0
    var wheelVelocity: Double = 0
    var poseVelocities: [Int: CarouselPoseVelocity] = [:]
    /// The stable wheel-card width used to convert scene depth millimetres.
    /// The engine supplies it even when every visible card has been promoted.
    var wheelCardWidth: Double = 0
    /// Continuous full-wheel stacking keys, including slots whose cards are promoted.
    /// Unlike visible array ranks these do not change when a card leaves the wheel.
    var wheelDepthKeys: [Int: Double] = [:]
    var glass: CarouselConfiguration.Glass = .init()
    /// Metal draws the cards as 3D slabs when enabled (never the native glass views).
    var card3D: CarouselConfiguration.Card3D = .init()
}

enum CarouselGeometry {
    /// Resolve physical elevation after screen-space motion and stacking have settled.
    /// Wheel cards stay just below zero; promotion raises a card above those layers.
    /// Elevation preserves the flat pose; turns use the shared scene camera.
    static func applyingSceneDepth(to frame: CarouselFrame) -> CarouselFrame {
        let nativeGlass = frame.glass.style == .liquidGlass && frame.glass.padding > 0
        guard frame.card3D.isEnabled, frame.card3D.sceneDepth, !nativeGlass else {
            // The legacy 3D slab (scene depth off) only turns about the vertical axis: no press tilt.
            let legacySlab = frame.card3D.isEnabled && !nativeGlass
            guard frame.wheel.contains(where: { $0.pose.sceneDepth != 0 || legacySlab && $0.pose.isTilted }) ||
                  frame.promoted.contains(where: { $0.pose.sceneDepth != 0 || legacySlab && $0.pose.isTilted })
            else { return frame }
            var result = frame
            for index in result.wheel.indices {
                result.wheel[index].pose.sceneDepth = 0
                if legacySlab { result.wheel[index].pose.tiltX = 0; result.wheel[index].pose.tiltY = 0 }
            }
            for index in result.promoted.indices {
                result.promoted[index].pose.sceneDepth = 0
                if legacySlab { result.promoted[index].pose.tiltX = 0; result.promoted[index].pose.tiltY = 0 }
            }
            return result
        }
        var result = frame
        let fallback = Double(frame.size.width) * (frame.size.height > 0 && frame.size.width / frame.size.height < 0.85 ? 0.66 : 0.56)
        let visibleWidth = frame.wheel.map { $0.pose.width }.filter { $0.isFinite && $0 > 0 }.max() ?? fallback
        let width = frame.wheelCardWidth.isFinite && frame.wheelCardWidth > 0 ? frame.wheelCardWidth : visibleWidth
        result.wheelCardWidth = max(0, width)
        let scale = result.wheelCardWidth / CarouselSlab.cardWidthMillimeters
        let spacing = scale * min(16, max(0, frame.card3D.wheelLayerSpacing.isFinite ? frame.card3D.wheelLayerSpacing : 4))
        let lift = scale * min(85.6, max(0, frame.card3D.selectionLift.isFinite ? frame.card3D.selectionLift : 24))
        let camera = CarouselSceneCamera(size: frame.size)
        let maximumElevation = camera.distance * 0.9
        func slotDepth(_ index: Int, fallbackKey: Double) -> Double {
            let key: Double
            if let supplied = frame.wheelDepthKeys[index], supplied.isFinite { key = supplied }
            else { key = fallbackKey }
            // Visible wheel slots stay inside ±1.75. A returning slot farther away
            // may be clamped at the front ceiling, but never gains a positive layer.
            return (min(2, key) - 2) * spacing
        }
        for rank in result.wheel.indices {
            let fallback = Double(rank) - Double(max(0, result.wheel.count - 1)) / 2
            let depth = slotDepth(result.wheel[rank].index, fallbackKey: fallback)
            if result.wheel[rank].pose.sceneDepth != depth { result.wheel[rank].pose.sceneDepth = depth }
        }
        for index in result.promoted.indices {
            let card = result.promoted[index]
            let pose = card.pose
            // Selection elevation follows the same spring as growth and turn,
            // including its bounce above the selected resting plane.
            let amount = pose.promotion.isFinite ? max(0, pose.promotion) : 0
            let dockingDepth = slotDepth(card.index, fallbackKey: 1 - Double(card.occluderIndices.count))
            let baseDepth = dockingDepth + (lift - dockingDepth) * amount
            // Each promoted card clears the fixed wheel ceiling independently.
            // Painter order still makes the hard halfway handoff; changing that
            // order cannot teleport another card's optical surface through space.
            let outer = pose.outerSize(padding: frame.glass.padding)
            let build = CarouselSlab.build(pose: pose, padding: frame.glass.padding, card3D: frame.card3D)
            let downwardExtent = abs(sin(pose.turn)) * Double(outer.width) / 2 + max(0, cos(pose.turn)) * build.thickness +
                abs(sin(pose.tiltX)) * Double(outer.height) / 2 + abs(sin(pose.tiltY)) * Double(outer.width) / 2
            let clearance = (0.5 + downwardExtent) / (1 + downwardExtent / camera.distance)
            let clearedDepth = max(baseDepth, clearance)
            let docking = smoothstep(0, 0.35, amount)
            let depth = min(maximumElevation, baseDepth + (clearedDepth - baseDepth) * docking)
            if result.promoted[index].pose.sceneDepth != depth { result.promoted[index].pose.sceneDepth = depth }
        }
        return result
    }

    static func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index % count) + count) % count
    }

    static func relative(_ index: Int, position: Double, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let n = Double(count)
        var value = (Double(index) - position).truncatingRemainder(dividingBy: n)
        if value >= n / 2 { value -= n }
        if value < -n / 2 { value += n }
        return value
    }

    static func nearestPosition(for index: Int, from position: Double, count: Int) -> Double {
        position + relative(wrappedIndex(index, count: count), position: position, count: count)
    }

    /// Stacking order along the wheel: higher keys draw above lower ones. Cards arriving
    /// in the travel `direction` (+1 while the position increases and cards move left)
    /// stay above the cards they pass, so steady motion never swaps a visible pair.
    static func stackKey(_ index: Int, position: Double, count: Int, direction: Int) -> Double {
        relative(index, position: position, count: count) * Double(direction < 0 ? -1 : 1)
    }

    /// The outer fade reaches zero before two slots away. Enumerate only the
    /// four potentially visible slots, even when the image list is very large.
    /// Back to front: departing cards first, arriving cards last.
    static func wheelIndices(position: Double, count: Int, direction: Int = 1) -> [Int] {
        guard count > 0, position.isFinite else { return [] }
        let candidates: [Int]
        if count <= 4 {
            candidates = Array(0..<count)
        } else {
            let normalized = position.truncatingRemainder(dividingBy: Double(count))
            let base = Int(floor(normalized))
            candidates = (-1...2).map { wrappedIndex(base + $0, count: count) }
        }
        return candidates.sorted {
            let first = stackKey($0, position: position, count: count, direction: direction)
            let second = stackKey($1, position: position, count: count, direction: direction)
            return first == second ? $0 < $1 : first < second
        }
    }

    static func cardHeight(size: CGSize, layout: CarouselConfiguration.Layout) -> Double {
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return 0 }
        return min(h * 0.627, w * (w / h < 0.85 ? 0.66 : 0.56) / layout.cardAspect) * layout.cardScale
    }

    static func spacing(size: CGSize, layout: CarouselConfiguration.Layout,
                        glass: CarouselConfiguration.Glass = .init()) -> Double {
        let gap = size.height > 0 && size.width / size.height < 0.85 ? 0.10 : 0.17
        return cardHeight(size: size, layout: layout) * layout.cardAspect + 2 * glass.padding + gap * Double(size.width) / 2
    }

    static func wheelPose(index: Int, position: Double, count: Int, size: CGSize,
                          layout: CarouselConfiguration.Layout,
                          glass: CarouselConfiguration.Glass = .init(),
                          cardLayout: CarouselCardLayout? = nil) -> CarouselPose {
        let offset = relative(index, position: position, count: count)
        let step = layout.wheelCurve * .pi / 6
        let spacing = spacing(size: size, layout: layout, glass: glass)
        let angle = offset * step
        let x = step < 0.00001 ? offset * spacing : spacing / step * sin(angle)
        let y = step < 0.00001 ? 0 : spacing / step * (1 - cos(angle))
        let side = 1 + (layout.sideScale - 1) * smoothstep(0, 1, abs(offset))
        let fadeEnd = min(1.75, Double(count) / 2 - 0.05)
        let fadeStart = min(1.15, max(0, fadeEnd - 0.6))
        let item = cardLayout?.validated(fallbackAspect: layout.cardAspect)
        let aspect = item?.aspectRatio ?? layout.cardAspect
        let baseHeight = cardHeight(size: size, layout: layout)
        let itemHeight = item.map { min(Double(size.height) * 0.627 * layout.cardScale,
            baseHeight * layout.cardAspect * $0.relativeWidth / aspect) } ?? baseHeight
        return CarouselPose(x: Double(size.width) / 2 + x, y: Double(size.height) * 0.48 + y,
                            height: itemHeight * side, angle: angle,
                            opacity: count <= 1 ? 1 : 1 - smoothstep(fadeStart, fadeEnd, abs(offset)),
                            aspect: aspect)
    }

    static func focusedPose(size: CGSize, glass: CarouselConfiguration.Glass = .init(),
                            aspect: Double = 0.8) -> CarouselPose {
        CarouselPose(x: Double(size.width) / 2, y: Double(size.height) / 2,
                     height: max(0, min(Double(size.height) - 48 - 2 * glass.padding,
                                        (Double(size.width) - 48 - 2 * glass.padding) / aspect)),
                     promotion: 1, aspect: aspect)
    }

    /// Viewing distance for a turning card, in points: twice its larger outer side, as
    /// SwiftUI's `rotation3DEffect(perspective: 0.5)`. Metal and Core Animation share it.
    static func turnDistance(outer: CGSize) -> Double {
        2 * max(1, Double(max(outer.width, outer.height)))
    }

    static func outerBounds(pose: CarouselPose, padding: Double = 0) -> CGRect {
        let size = pose.outerSize(padding: padding)
        let bounds = CGRect(x: -size.width / 2, y: -size.height / 2,
                            width: size.width, height: size.height)
        return bounds.applying(CGAffineTransform(translationX: pose.x, y: pose.y).rotated(by: pose.angle))
    }

    static func usesSceneDepth(_ frame: CarouselFrame) -> Bool {
        frame.card3D.isEnabled && frame.card3D.sceneDepth &&
            !(frame.glass.style == .liquidGlass && frame.glass.padding > 0)
    }

    static func sceneCardGeometry(pose: CarouselPose, frame: CarouselFrame) -> CarouselSceneCardGeometry {
        CarouselSceneCardGeometry(pose: pose, padding: frame.glass.padding, card3D: frame.card3D,
                                  camera: CarouselSceneCamera(size: frame.size))
    }

    /// Bounds of the displayed scene slab, or the established flat/native outline.
    static func outerBounds(pose: CarouselPose, frame: CarouselFrame) -> CGRect {
        usesSceneDepth(frame) ? sceneCardGeometry(pose: pose, frame: frame).projectedBounds() :
            outerBounds(pose: pose, padding: frame.glass.padding)
    }

    static func outerRoundedPath(pose: CarouselPose, padding: Double = 0) -> CGPath {
        let size = pose.outerSize(padding: padding)
        let radius = pose.outerCornerRadius(padding: padding)
        let bounds = CGRect(x: -size.width / 2, y: -size.height / 2,
                            width: size.width, height: size.height)
        let path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        var transform = CGAffineTransform(translationX: pose.x, y: pose.y).rotated(by: pose.angle)
        return path.copy(using: &transform) ?? path
    }

    static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    static func contains(_ point: CGPoint, pose: CarouselPose, padding: Double = 0,
                         cornerRadius: Double? = nil) -> Bool {
        guard pose.height > 0, pose.opacity > 0.02 else { return false }
        let dx = Double(point.x) - pose.x, dy = Double(point.y) - pose.y
        let x = abs(dx * cos(pose.angle) + dy * sin(pose.angle))
        let y = abs(-dx * sin(pose.angle) + dy * cos(pose.angle))
        let size = pose.outerSize(padding: padding)
        let radius = cornerRadius ?? pose.outerCornerRadius(padding: padding)
        let qx = x - Double(size.width) / 2 + radius, qy = y - Double(size.height) / 2 + radius
        return min(max(qx, qy), 0) + hypot(max(qx, 0), max(qy, 0)) <= radius
    }

    /// Hit the outline in the displayed frame, including its physical 3D corners.
    /// Native glass keeps its flat card shape even when the 3D setting is enabled.
    static func contains(_ point: CGPoint, pose: CarouselPose, frame: CarouselFrame) -> Bool {
        guard pose.height > 0, pose.opacity > 0.02 else { return false }
        if usesSceneDepth(frame) { return sceneCardGeometry(pose: pose, frame: frame).hit(at: point) != nil }
        let usesNativeGlass = frame.glass.style == .liquidGlass && frame.glass.padding > 0
        let radius = frame.card3D.isEnabled && !usesNativeGlass ?
            CarouselSlab.cornerRadius(pose: pose, padding: frame.glass.padding, card3D: frame.card3D) :
            pose.outerCornerRadius(padding: frame.glass.padding)
        return contains(point, pose: pose, padding: frame.glass.padding, cornerRadius: radius)
    }

    static func hitTest(_ point: CGPoint, frame: CarouselFrame) -> Int? {
        if usesSceneDepth(frame) {
            let displayed = applyingSceneDepth(to: frame)
            let promotedIndices = Set(displayed.promoted.map(\.index))
            let cards = displayed.wheel.filter { !promotedIndices.contains($0.index) } + displayed.promoted
            var nearest: (index: Int, distance: Double)?
            for card in cards where card.pose.height > 0 && card.pose.opacity > 0.02 {
                guard let hit = sceneCardGeometry(pose: card.pose, frame: displayed).hit(at: point) else { continue }
                // A transparent margin still belongs to its nearest plastic card.
                // Coincident surfaces keep the displayed order as their tie-break.
                if nearest == nil || hit.distance <= nearest!.distance + 0.001 {
                    nearest = (card.index, hit.distance)
                }
            }
            return nearest?.index
        }
        if frame.glass.style == .liquidGlass && frame.glass.padding > 0 {
            return CarouselNativeCardStack.cards(in: frame).reversed().first {
                contains(point, pose: $0.pose, padding: frame.glass.padding)
            }?.index
        }
        for card in frame.promoted.reversed() where contains(point, pose: card.pose, frame: frame) {
            let covered = card.occlusion > 0.5 && frame.wheel.contains {
                card.occluderIndices.contains($0.index) && contains(point, pose: $0.pose, frame: frame)
            }
            if !covered { return card.index }
        }
        for card in frame.wheel.reversed() where contains(point, pose: card.pose, frame: frame) { return card.index }
        return nil
    }
}
