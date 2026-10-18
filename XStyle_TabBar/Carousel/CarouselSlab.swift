import CoreGraphics
import Foundation
import simd

/// One camera for card visibility, projected content, touch hits and optical paths.
/// World units are UIKit points at z = 0;
/// x points right, y down, and positive z approaches the viewer.
struct CarouselSceneCamera {
    let eye: SIMD3<Double>
    let distance: Double

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, Double(size.width)) : 0
        let height = size.height.isFinite ? max(0, Double(size.height)) : 0
        distance = max(1, 1.2 * max(width, height))
        eye = SIMD3(width / 2, height / 2, distance)
    }

    func project(_ point: SIMD3<Double>) -> SIMD2<Double> {
        let scale = distance / max(0.000001, distance - point.z)
        return SIMD2(eye.x + (point.x - eye.x) * scale,
                     eye.y + (point.y - eye.y) * scale)
    }

    func ray(through point: SIMD2<Double>) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        (eye, simd_normalize(SIMD3(point.x - eye.x, point.y - eye.y, -distance)))
    }
}

/// A rigid card under the shared camera: one uniform scale followed by its in-plane
/// rotation and turn. Elevation deprojects the flat pose so its centre and size remain
/// fixed; a turning card uses the same perspective as every other scene surface.
struct CarouselSceneCardTransform {
    let slabToScene: simd_double4x4
    let sceneToSlab: simd_double4x4
    let normalToScene: simd_double3x3

    init(pose: CarouselPose, padding: Double, camera: CarouselSceneCamera) {
        let elevation = pose.sceneDepth.isFinite ? min(camera.distance * 0.95, pose.sceneDepth) : 0
        let scale = (camera.distance - elevation) / camera.distance
        let offset = SIMD2(pose.x - camera.eye.x, pose.y - camera.eye.y)
        let angle = pose.angle.isFinite ? pose.angle : 0
        let turn = pose.turn.isFinite ? pose.turn : 0
        let tiltX = pose.tiltX.isFinite ? pose.tiltX : 0, tiltY = pose.tiltY.isFinite ? pose.tiltY : 0
        // Rz(angle)·Ry(tiltY)·Rx(tiltX)·Ry(turn). Scene z points at the camera, so a positive
        // turn or tiltY sends the right edge away and a positive tiltX the bottom edge.
        func yaw(_ b: Double) -> simd_double3x3 {
            simd_double3x3(columns: (SIMD3(cos(b), 0, -sin(b)), SIMD3(0, 1, 0), SIMD3(sin(b), 0, cos(b))))
        }
        let pitch = simd_double3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, cos(tiltX), -sin(tiltX)),
                                             SIMD3(0, sin(tiltX), cos(tiltX))))
        let roll = simd_double3x3(columns: (SIMD3(cos(angle), sin(angle), 0), SIMD3(-sin(angle), cos(angle), 0),
                                            SIMD3(0, 0, 1)))
        let rotation = roll * yaw(tiltY) * pitch * yaw(turn)
        let x = scale * rotation.columns.0
        let y = scale * rotation.columns.1
        let z = scale * rotation.columns.2
        let origin = SIMD3(camera.eye.x + scale * offset.x,
                           camera.eye.y + scale * offset.y, elevation)
        let matrix = simd_double4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(origin, 1)))
        slabToScene = matrix
        let inverse = simd_inverse(matrix)
        sceneToSlab = inverse
        normalToScene = simd_transpose(simd_double3x3(columns: (
            SIMD3(inverse.columns.0.x, inverse.columns.0.y, inverse.columns.0.z),
            SIMD3(inverse.columns.1.x, inverse.columns.1.y, inverse.columns.1.z),
            SIMD3(inverse.columns.2.x, inverse.columns.2.y, inverse.columns.2.z))))
    }

    func worldPoint(_ point: SIMD3<Double>) -> SIMD3<Double> {
        xyz(slabToScene * SIMD4(point, 1))
    }

    func localPoint(_ point: SIMD3<Double>) -> SIMD3<Double> {
        xyz(sceneToSlab * SIMD4(point, 1))
    }

    /// Directions retain their magnitude so a ray's parameter measures world distance.
    func worldDirection(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        xyz(slabToScene * SIMD4(direction, 0))
    }

    func localDirection(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        xyz(sceneToSlab * SIMD4(direction, 0))
    }

    func worldNormal(_ normal: SIMD3<Double>) -> SIMD3<Double> {
        let transformed = normalToScene * normal
        return simd_length_squared(transformed) > 0.00000001 ? simd_normalize(transformed) : SIMD3(0, 0, 1)
    }

    private func xyz(_ value: SIMD4<Double>) -> SIMD3<Double> {
        SIMD3(value.x, value.y, value.z)
    }
}

/// Shared CPU geometry for raster bounds, camera hits and native content planes.
/// Local dimensions stay in pose points; the scene transform supplies uniform scale.
struct CarouselSceneCardGeometry {
    struct Hit {
        /// Distance along the unit world camera ray, in scene points.
        let distance: Double
        let localPoint: SIMD3<Double>
        let worldPoint: SIMD3<Double>
        let localNormal: SIMD3<Double>
    }

    let camera: CarouselSceneCamera
    let transform: CarouselSceneCardTransform
    let build: CarouselSlab.Build
    let half: SIMD2<Double>
    let cornerRadius: Double
    let exponent: Double

    init(pose: CarouselPose, padding: Double, card3D: CarouselConfiguration.Card3D,
         camera: CarouselSceneCamera) {
        self.camera = camera
        transform = CarouselSceneCardTransform(pose: pose, padding: padding, camera: camera)
        build = CarouselSlab.build(pose: pose, padding: padding, card3D: card3D)
        let outer = pose.outerSize(padding: padding)
        half = SIMD2(Double(outer.width) / 2, Double(outer.height) / 2)
        cornerRadius = CarouselSlab.cornerRadius(pose: pose, padding: padding, card3D: card3D)
        exponent = CarouselSlab.exponent(card3D)
    }

    func project(_ localPoint: SIMD3<Double>) -> SIMD2<Double> {
        camera.project(transform.worldPoint(localPoint))
    }

    /// Maps local (x, y, 1) to global screen homogeneous coordinates at a chosen z.
    /// The paper's front and back use `build.paperTop` and `build.paperBottom`.
    func screenHomography(depth: Double = 0) -> simd_double3x3 {
        let matrix = transform.slabToScene
        func direction(_ column: SIMD4<Double>) -> SIMD3<Double> {
            SIMD3(camera.distance * column.x - camera.eye.x * column.z,
                  camera.distance * column.y - camera.eye.y * column.z, -column.z)
        }
        let origin = matrix.columns.3 + matrix.columns.2 * depth
        return simd_double3x3(columns: (direction(matrix.columns.0), direction(matrix.columns.1),
            SIMD3(camera.distance * origin.x - camera.eye.x * origin.z,
                  camera.distance * origin.y - camera.eye.y * origin.z,
                  camera.distance - origin.z)))
    }

    /// Global screen points enclosing the complete slab, including its back and sides.
    /// Projecting the convex box corners conservatively encloses the rounded laminate.
    func projectedBounds(margin: Double = 0) -> CGRect {
        guard half.x > 0, half.y > 0 else { return .null }
        var lower = SIMD2<Double>(repeating: .infinity)
        var upper = SIMD2<Double>(repeating: -.infinity)
        for x in [-half.x, half.x] {
            for y in [-half.y, half.y] {
                for z in [0, -build.thickness] {
                    let point = project(SIMD3(x, y, z))
                    guard point.x.isFinite, point.y.isFinite else { return .null }
                    lower = pointwiseMin(lower, point)
                    upper = pointwiseMax(upper, point)
                }
            }
        }
        let outset = margin.isFinite ? max(0, margin) : 0
        return CGRect(x: lower.x - outset, y: lower.y - outset,
                      width: upper.x - lower.x + 2 * outset,
                      height: upper.y - lower.y + 2 * outset)
    }

    /// The same convex rounded laminate and Newton tolerances as the Metal primary ray.
    /// Inverting the ray without normalizing its direction retains world-distance t.
    func hit(at screenPoint: CGPoint) -> Hit? {
        guard screenPoint.x.isFinite, screenPoint.y.isFinite, half.x > 0, half.y > 0 else { return nil }
        let ray = camera.ray(through: SIMD2(Double(screenPoint.x), Double(screenPoint.y)))
        let origin = transform.localPoint(ray.origin)
        let direction = transform.localDirection(ray.direction)
        let lower = SIMD3(-half.x - 1, -half.y - 1, -build.thickness - 1)
        let upper = SIMD3(half.x + 1, half.y + 1, 1)
        var near = 0.0, far = Double.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-9 {
                guard origin[axis] >= lower[axis], origin[axis] <= upper[axis] else { return nil }
            } else {
                let a = (lower[axis] - origin[axis]) / direction[axis]
                let b = (upper[axis] - origin[axis]) / direction[axis]
                near = max(near, min(a, b))
                far = min(far, max(a, b))
            }
        }
        guard near <= far, near.isFinite, far.isFinite else { return nil }
        var distance = near
        for _ in 0..<16 {
            let point = origin + direction * distance
            let outside = outsideDistance(point)
            if outside < 0.001 { return makeHit(distance: distance, point: point) }
            let slope = simd_dot(gradient(point), direction)
            guard slope < -0.0001 else { return nil }
            distance = min(distance - outside / slope, far)
        }
        let point = origin + direction * distance
        return outsideDistance(point) < 0.01 ? makeHit(distance: distance, point: point) : nil
    }

    /// The first printed paper plane along the camera ray. Plastic margins stay clear.
    /// Its rounded bounds and plane depths match the source scene's opaque surfaces.
    func paperHit(at screenPoint: CGPoint) -> Hit? {
        guard screenPoint.x.isFinite, screenPoint.y.isFinite else { return nil }
        let ray = camera.ray(through: SIMD2(Double(screenPoint.x), Double(screenPoint.y)))
        let origin = transform.localPoint(ray.origin)
        let direction = transform.localDirection(ray.direction)
        guard abs(direction.z) > 0.000001 else { return nil }
        let paperHalf = half - SIMD2<Double>(repeating: build.margin)
        let paperRadius = max(0, cornerRadius - build.margin)
        var nearest: Hit?
        for (depth, normal) in [(build.paperTop, SIMD3<Double>(0, 0, 1)),
                                (build.paperBottom, SIMD3<Double>(0, 0, -1))] {
            let distance = (depth - origin.z) / direction.z
            guard distance >= 0, distance.isFinite else { continue }
            let point = origin + direction * distance
            let q = SIMD2(abs(point.x) - paperHalf.x + paperRadius,
                          abs(point.y) - paperHalf.y + paperRadius)
            let outside = min(max(q.x, q.y), 0) + simd_length(pointwiseMax(q, .zero)) - paperRadius
            guard outside <= 0 else { continue }
            if nearest == nil || distance < nearest!.distance {
                nearest = Hit(distance: distance, localPoint: point,
                              worldPoint: transform.worldPoint(point), localNormal: normal)
            }
        }
        return nearest
    }

    private func makeHit(distance: Double, point: SIMD3<Double>) -> Hit {
        var normal = gradient(point)
        if simd_length_squared(normal) > 0.000000000001 {
            normal = simd_normalize(normal)
        } else {
            let outline = outline(point)
            let top = -point.z, back = point.z + build.thickness
            normal = max(outline.inward, 0) < min(top, back)
                ? SIMD3(outline.normal.x, outline.normal.y, 0)
                : SIMD3(0, 0, top <= back ? 1 : -1)
        }
        return Hit(distance: distance, localPoint: point, worldPoint: transform.worldPoint(point),
                   localNormal: normal)
    }

    private func outline(_ point: SIMD3<Double>) -> (inward: Double, normal: SIMD2<Double>) {
        let q = SIMD2(abs(point.x) - half.x + cornerRadius, abs(point.y) - half.y + cornerRadius)
        let side = SIMD2<Double>(point.x >= 0 ? 1 : -1, point.y >= 0 ? 1 : -1)
        if q.x > 0, q.y > 0 {
            let length = simd_length(q)
            return (cornerRadius - length, q / max(length, 0.000001) * side)
        }
        if q.x > q.y { return (cornerRadius - q.x, SIMD2(side.x, 0)) }
        return (cornerRadius - q.y, SIMD2(0, side.y))
    }

    private func outsideDistance(_ point: SIMD3<Double>) -> Double {
        let across = max(build.bevel - outline(point).inward, 0)
        let along = max(point.z + build.bevel, build.bevel - build.thickness - point.z, 0)
        return pow(pow(across, exponent) + pow(along, exponent), 1 / exponent) - build.bevel
    }

    private func gradient(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let outline = outline(point)
        let across = max(build.bevel - outline.inward, 0)
        let top = point.z + build.bevel, back = build.bevel - build.thickness - point.z
        let along = max(top, back, 0)
        let norm = pow(pow(across, exponent) + pow(along, exponent), 1 / exponent)
        guard norm > 0.000001 else { return .zero }
        let outward = pow(across / norm, exponent - 1)
        let upward = pow(along / norm, exponent - 1)
        return SIMD3(outline.normal.x * outward, outline.normal.y * outward, top >= back ? upward : -upward)
    }
}

/// The material shadow grows continuously as a card lifts from the wheel.
/// Legacy values are retained for the original appearance and flat cards.
struct CarouselCardShadow {
    let blur: Double
    let offset: Double
    let alpha: Double

    init(promotion: Double, softShadows: Bool) {
        let amount = promotion.isFinite ? min(1, max(0, promotion)) : 0
        blur = softShadows ? 3 + 12 * amount : 1 + 14 * amount
        offset = softShadows ? 2 + 10 * amount : 12 * amount
        alpha = softShadows ? 0.075 + 0.145 * amount : 0.22 * amount
    }
}

/// The 3D card (`CarouselConfiguration.Card3D`), laminated like the onboarding project's: a
/// paper sheet carrying the image, sealed in a clear plastic slab. What the renderer, the
/// slab shaders and the views over a card share. Card space has its origin at the card's
/// centre, x right, y down and z toward the viewer; the face lies at z = 0 and the back at
/// z = -thickness. Millimetres are measured on an 85.6 mm-wide card and scale with each
/// card's width.
enum CarouselSlab {
    /// The card width a thickness in millimetres is measured against: a credit card's.
    static let cardWidthMillimeters = 85.6
    /// The paper where nothing is printed: linear grey.
    static let stock: Float = 0.9
    /// Acrylic.
    static let refractiveIndex: Float = 1.49
    /// The colour 10 mm of the plastic leaves white light (the onboarding's).
    static let tint = SIMD3<Double>(0.80, 0.93, 0.91)
    static let tintDistanceMillimeters = 10.0
    /// The paper sheet and the plastic above it; the plastic below takes the rest of the
    /// thickness, never less than its minimum.
    static let paperMillimeters = 0.2
    static let aboveMillimeters = 0.28
    static let minimumBelowMillimeters = 0.02

    /// A card's build in points, for a card whose outline (its frame included) is `outer`.
    struct Build: Equatable {
        var thickness: Double
        /// The rounded edge's radius: never more than half the thickness or most of a corner.
        var bevel: Double
        /// From the outline to the paper's edge: the clear plastic, never narrower than the
        /// rounded edge, nor wider than a quarter of the card.
        var margin: Double
        /// z of the paper's printed face, then of its back.
        var paperTop: Double
        var paperBottom: Double
    }

    /// The slab shaders' `carouselSlabShape` computes the same build.
    static func build(outer: CGSize, cornerRadius: Double, card3D: CarouselConfiguration.Card3D) -> Build {
        let width = max(0, Double(outer.width))
        func points(_ millimeters: Double) -> Double { width * max(0, millimeters) / cardWidthMillimeters }
        let thickness = points(card3D.thickness)
        let bevel = max(0, min(card3D.bevelFraction * thickness, thickness / 2, 0.9 * cornerRadius))
        let margin = min(max(points(card3D.margin), bevel), 0.25 * min(width, max(0, Double(outer.height))))
        let layers = self.layers(thickness: card3D.thickness)
        let paperTop = -points(layers.above)
        return Build(thickness: thickness, bevel: bevel, margin: margin,
                     paperTop: paperTop, paperBottom: paperTop - points(layers.paper))
    }

    static func build(pose: CarouselPose, padding: Double, card3D: CarouselConfiguration.Card3D) -> Build {
        build(outer: pose.outerSize(padding: padding), cornerRadius: cornerRadius(pose: pose, padding: padding, card3D: card3D),
              card3D: card3D)
    }

    /// The image's corner radius for a 3D card, before the clear margin: `card3D.cornerRadius`
    /// millimetres of the image's width, as flat cards' `imageCornerRadius` is 0.034 of it.
    static func imageCornerRadius(pose: CarouselPose, card3D: CarouselConfiguration.Card3D) -> Double {
        max(0, pose.width) * max(0, card3D.cornerRadius) / cardWidthMillimeters
    }

    /// The outline's corner radius, as `CarouselPose.outerCornerRadius` with the 3D card's corners.
    static func cornerRadius(pose: CarouselPose, padding: Double, card3D: CarouselConfiguration.Card3D) -> Double {
        let padding = padding.isFinite ? max(0, padding) : 8
        let size = pose.outerSize(padding: padding)
        return min(Double(min(size.width, size.height)) / 2, imageCornerRadius(pose: pose, card3D: card3D) + padding)
    }

    /// The paper's corner radius: the outline's corner centres, inside the clear margin.
    static func paperCornerRadius(pose: CarouselPose, padding: Double, card3D: CarouselConfiguration.Card3D) -> Double {
        max(0, cornerRadius(pose: pose, padding: padding, card3D: card3D) -
            build(pose: pose, padding: padding, card3D: card3D).margin)
    }

    /// The paper and the plastic above it, in millimetres, for a card `thickness` thick:
    /// the paper, then the plastic above, give way to the minimum below.
    static func layers(thickness: Double) -> (above: Double, paper: Double) {
        let room = max(thickness - minimumBelowMillimeters, 0)
        let paper = min(paperMillimeters, room * 0.9)
        return (min(aboveMillimeters, room - paper), paper)
    }

    /// The edge's profile exponent: |x|^e + |y|^e = 1, a circle at e = 2.
    static func exponent(_ card3D: CarouselConfiguration.Card3D) -> Double {
        2 + 2 * min(1, max(0, card3D.softness))
    }

    /// The plastic's absorption per card width (Beer–Lambert), per channel.
    static var absorption: SIMD3<Float> {
        let scale = cardWidthMillimeters / tintDistanceMillimeters
        return SIMD3(Float(-log(tint.x) * scale), Float(-log(tint.y) * scale), Float(-log(tint.z) * scale))
    }

    /// A card point as a card turned by `turn` about its vertical axis shows it, seen from
    /// `distance` points above its centre: an offset from the card's centre, before its
    /// in-plane tilt. The slab shaders and `CarouselTurnTransform` project the same way.
    static func project(_ point: SIMD3<Double>, turn: Double, distance: Double) -> SIMD2<Double> {
        let c = cos(turn), s = sin(turn)
        let x = point.x * c + point.z * s
        let z = -point.x * s + point.z * c
        let w = 1 - z / max(1, distance)
        return SIMD2(x / w, point.y / w)
    }

    /// What a turning slab can draw, as an offset box before its in-plane tilt: its eight
    /// box corners and, for a lifted card, its shadow's box on the face plane, projected,
    /// then grown by `margin`. Projection keeps the convex slab inside its corners' bounds.
    static func screenBox(half: SIMD2<Double>, thickness: Double, turn: Double, distance: Double,
                          shadowCenter: SIMD2<Double>?, shadowHalf: SIMD2<Double>,
                          margin: Double) -> (center: SIMD2<Double>, half: SIMD2<Double>) {
        var corners: [SIMD3<Double>] = []
        for x in [-half.x, half.x] {
            for y in [-half.y, half.y] {
                corners.append(SIMD3(x, y, 0))
                corners.append(SIMD3(x, y, -max(0, thickness)))
            }
        }
        if let shadowCenter {
            for x in [-shadowHalf.x, shadowHalf.x] {
                for y in [-shadowHalf.y, shadowHalf.y] {
                    corners.append(SIMD3(shadowCenter.x + x, shadowCenter.y + y, 0))
                }
            }
        }
        var lower = SIMD2<Double>(repeating: .infinity), upper = SIMD2<Double>(repeating: -.infinity)
        for corner in corners {
            let p = project(corner, turn: turn, distance: distance)
            lower = pointwiseMin(lower, p)
            upper = pointwiseMax(upper, p)
        }
        return ((lower + upper) / 2, (upper - lower) / 2 + margin)
    }

    /// How far the print, and a live view laid over a card's face, stays inside the card's
    /// image area: to the paper, inside the clear margin (a frame's padding already holds
    /// that much of it).
    static func faceInset(pose: CarouselPose, padding: Double, card3D: CarouselConfiguration.Card3D) -> Double {
        guard card3D.isEnabled else { return 0 }
        return max(0, build(pose: pose, padding: padding, card3D: card3D).margin - max(0, padding))
    }
}
