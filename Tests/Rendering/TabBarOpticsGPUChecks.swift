import Foundation
import Metal
import CoreGraphics

struct Uniforms {
    var geometry: SIMD4<Float>
    var capture: SIMD4<Float>
    var material: SIMD4<Float>
    var visibleRect: SIMD4<Float>
    var previousCapture: SIMD4<Float>
    var sceneRect: SIMD4<Float>
    var feed: SIMD4<Float>
    var reflection = SIMD4<Float>.zero
    var surface = SIMD4<Float>.zero
    var lighting = SIMD4<Float>.zero

    mutating func apply(_ settings: TabBarReflectionSettings) {
        let settings = settings.sanitized()
        material.x = Float(settings.lightDirectionDegrees) * .pi / 180
        material.y = Float(settings.sharpHighlight)
        material.z = Float(settings.samplingDistance)
        reflection = SIMD4(Float(settings.reflectionStrength), Float(settings.reflectionWidth),
                           Float(settings.saturation), Float(settings.softness))
        surface = SIMD4(Float(settings.surfaceOpacity), Float(settings.faceWash),
                        settings.mode == .faceAndEdges ? 1 : 0, Float(settings.edgeDarkening))
        lighting = SIMD4(Float(settings.softGlow), Float(settings.sharpHighlightWidth),
                         Float(settings.softGlowWidth), Float(settings.warmCoolBalance))
    }
}
struct Scene {
    var name: String
    var width: Int
    var height: Int
    var origin: SIMD2<Float>
    var sourceSize: SIMD2<Int>
    var visible: SIMD4<Float>?
    var visibleRect: SIMD4<Float> { visible ?? SIMD4(0, 0, Float(sourceSize.x), Float(sourceSize.y)) }
}
struct Result {
    let width: Int
    let height: Int
    let values: [SIMD4<Float>]
    func pixel(_ x: Float, _ y: Float) -> SIMD4<Float> {
        values[min(height - 1, max(0, Int(y * 2))) * width + min(width - 1, max(0, Int(x * 2)))]
    }
}
let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: TabBarOpticsGPUChecks.swift /path/to/TabBarOptics.metallib")
}
let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
func makePipeline(_ fragment: String, format: MTLPixelFormat = .rgba32Float) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "tabBarOpticsVertex")
    descriptor.fragmentFunction = library.makeFunction(name: fragment)
    descriptor.colorAttachments[0].pixelFormat = format
    return try device.makeRenderPipelineState(descriptor: descriptor)
}
let opticsPipeline = try makePipeline("tabBarOpticsFragment")
let drawablePipeline = try makePipeline("tabBarOpticsFragment", format: .bgra8Unorm_srgb)
let copyPipeline = try makePipeline("tabBarSceneCopyFragment")
let prepareUIPipeline = try makePipeline("tabBarPrepareUIFragment", format: .rgba16Float)
let washPipeline = try makePipeline("tabBarWashFragment", format: .rgba16Float)
let washDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
    width: 64, height: 1, mipmapped: false)
washDescriptor.storageMode = .private
washDescriptor.hazardTrackingMode = .tracked
washDescriptor.usage = [.renderTarget, .shaderRead]
let washTexture = device.makeTexture(descriptor: washDescriptor)!
let colors: [SIMD4<Float>] = [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 1)]
var checks = 0
var frameCount = 0
var preparationPasses = 0
var washPasses = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { print("FAIL: \(message)"); exit(1) }
    print("PASS: \(message)")
}
func target(_ width: Int, _ height: Int) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}
func prepareUI(_ source: MTLTexture, command: MTLCommandBuffer) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
        width: source.width, height: source.height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    let output = device.makeTexture(descriptor: descriptor)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(prepareUIPipeline)
    encoder.setFragmentTexture(source, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    preparationPasses += 1
    return output
}
func prepareWash(_ uniforms: Uniforms, previous: MTLTexture, current: MTLTexture,
                 scene: MTLTexture, command: MTLCommandBuffer) {
    guard uniforms.material.w < 0.5, uniforms.surface.z > 0.5, uniforms.surface.y > 0 else { return }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = washTexture
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(washPipeline)
    var uniforms = uniforms
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.setFragmentTexture(previous, index: 0)
    encoder.setFragmentTexture(current, index: 1)
    encoder.setFragmentTexture(scene, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    washPasses += 1
}
func execute(_ output: MTLTexture, _ source: MTLTexture, _ pipeline: MTLRenderPipelineState, uniforms: Uniforms?, current: MTLTexture? = nil, scene: MTLTexture? = nil, copyRect: SIMD4<Float>? = nil) throws -> Result {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    let command = queue.makeCommandBuffer()!
    let preparedSource = pipeline === opticsPipeline ? prepareUI(source, command: command) : source
    let preparedCurrent: MTLTexture
    if pipeline === opticsPipeline, let current, current !== source {
        preparedCurrent = prepareUI(current, command: command)
    } else { preparedCurrent = preparedSource }
    if pipeline === opticsPipeline, let uniforms {
        prepareWash(uniforms, previous: preparedSource, current: preparedCurrent,
                    scene: scene ?? source, command: command)
    }
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline)
    if var uniforms {
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    }
    if var copyRect {
        encoder.setFragmentBytes(&copyRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
    }
    encoder.setFragmentTexture(preparedSource, index: 0)
    encoder.setFragmentTexture(preparedCurrent, index: 1)
    encoder.setFragmentTexture(scene ?? source, index: 2)
    encoder.setFragmentTexture(washTexture, index: 3)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    if let error = command.error { throw error }
    frameCount += 1
    var values = [SIMD4<Float>](repeating: .zero, count: output.width * output.height)
    output.getBytes(&values, bytesPerRow: output.width * MemoryLayout<SIMD4<Float>>.stride, from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0)
    if pipeline === opticsPipeline {
        // Float targets expose the shader's hardware-encoding compensation.
        // Convert that to linear-premultiplied values for color/optics assertions.
        // Separate raw _srgb byte tests below verify actual compositor output.
        values = values.map { value in
            guard value.w > 0 else { return .zero }
            return SIMD4(linear(srgb(value.x) / value.w) * value.w,
                         linear(srgb(value.y) / value.w) * value.w,
                         linear(srgb(value.z) / value.w) * value.w, value.w)
        }
    }
    return Result(width: output.width, height: output.height, values: values)
}
func linear(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
func srgb(_ x: Float) -> Float { x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055 }
func texture(_ size: SIMD2<Int>, onePixel: Bool = false, gpuPremultiplied: Bool = false, color: (SIMD2<Float>) -> SIMD4<Float>) -> MTLTexture {
    let scene = Scene(name: "source", width: 0, height: 0, origin: .zero, sourceSize: size)
    let onePixelSource = onePixel
    let width = onePixelSource ? 1 : scene.sourceSize.x * 2
    let height = onePixelSource ? 1 : scene.sourceSize.y * 2
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let point = SIMD2((Float(x) + 0.5) * Float(scene.sourceSize.x) / Float(width), (Float(y) + 0.5) * Float(scene.sourceSize.y) / Float(height))
            let value = color(point)
            let offset = (y * width + x) * 4
            // UIKit premultiplies encoded RGB; Carousel premultiplies linear RGB
            // before its sRGB render target encodes. Exercise both conventions.
            for channel in 0..<3 {
                let encoded = gpuPremultiplied ? srgb(value[2 - channel]) :
                    srgb(value[2 - channel] / max(value.w, 1e-6)) * value.w
                bytes[offset + channel] = UInt8(max(0, min(255, (encoded * 255).rounded())))
            }
            bytes[offset + 3] = UInt8(max(0, min(255, (value.w * 255).rounded())))
        }
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpuPremultiplied ? .bgra8Unorm_srgb : .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let source = device.makeTexture(descriptor: descriptor)!
    source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
    return source
}
func render(_ scene: Scene, reduce: Bool = false, dark: Bool = false, onePixelSource: Bool = false,
            overrides: ((inout Uniforms) -> Void)? = nil, color: (SIMD2<Float>) -> SIMD4<Float>) throws -> Result {
    let source = texture(scene.sourceSize, onePixel: onePixelSource, color: color)
    var uniforms = Uniforms(
        geometry: SIMD4(Float(scene.width), Float(scene.height), 2, dark ? 1 : 0),
        capture: SIMD4(scene.origin.x, scene.origin.y, Float(scene.sourceSize.x), Float(scene.sourceSize.y)),
        material: SIMD4(-25 * .pi / 180, 1.5, 96, reduce ? 1 : 0),
        visibleRect: scene.visibleRect,
        previousCapture: SIMD4(0, 0, Float(scene.sourceSize.x), Float(scene.sourceSize.y)),
        sceneRect: .zero,
        feed: SIMD4(0, 0, 1, 0)
    )
    uniforms.apply(.defaults)
    overrides?(&uniforms)
    return try execute(target(scene.width * 2, scene.height * 2), source, opticsPipeline, uniforms: uniforms)
}
func distance(_ image: Result, x: Int, y: Int) -> Float {
    let halfWidth = Float(image.width) / 4, halfHeight = Float(image.height) / 4
    let radius = min(halfWidth, halfHeight)
    let px = (Float(x) + 0.5) / 2 - halfWidth, py = (Float(y) + 0.5) / 2 - halfHeight
    let dx = px - min(max(px, -(halfWidth - radius)), halfWidth - radius)
    let dy = py - min(max(py, -(halfHeight - radius)), halfHeight - radius)
    return sqrt(dx * dx + dy * dy) - radius
}
func validate(_ image: Result, name: String) {
    let valid = image.values.allSatisfy { p in
        p.x.isFinite && p.y.isFinite && p.z.isFinite && p.w.isFinite && p.w >= 0 && p.w <= 1 &&
        p.x >= 0 && p.y >= 0 && p.z >= 0 && p.x <= p.w + 1e-6 && p.y <= p.w + 1e-6 && p.z <= p.w + 1e-6
    }
    check(valid, "\(name): every output pixel finite and premultiplied")
    check(image.values.enumerated().allSatisfy { index, pixel in distance(image, x: index % image.width, y: index / image.width) < 0.25001 || pixel == .zero }, "\(name): every pixel beyond antialiased capsule transparent")
}
func difference(_ a: Result, _ b: Result) -> Float {
    zip(a.values, b.values).reduce(Float(0)) { previous, pair in
        let delta = pair.0 - pair.1
        return max(previous, max(abs(delta.x), max(abs(delta.y), max(abs(delta.z), abs(delta.w)))))
    }
}
func bandColor(_ scene: Scene, _ point: SIMD2<Float>) -> SIMD4<Float> {
    let local = point - scene.origin
    let position = scene.height > scene.width ? local.y / Float(scene.height) : local.x / Float(scene.width)
    return colors[max(0, min(2, Int(floor(position * 3))))]
}
let vertical = Scene(name: "vertical", width: 44, height: 206, origin: SIMD2(96, 96), sourceSize: SIMD2(236, 398))
let horizontal = Scene(name: "horizontal", width: 360, height: 60, origin: SIMD2(96, 96), sourceSize: SIMD2(552, 252))
let scenes = [vertical, horizontal,
    Scene(name: "vertical-outside-source", width: 44, height: 206, origin: SIMD2(248, 96), sourceSize: SIMD2(240, 398)),
    Scene(name: "horizontal-outside-source", width: 360, height: 60, origin: SIMD2(96, 228), sourceSize: SIMD2(552, 220))
]
for scene in scenes {
    let red = try render(scene) { _ in colors[0] }
    let blue = try render(scene) { _ in colors[2] }

    validate(red, name: "\(scene.name) red frame")
    validate(blue, name: "\(scene.name) blue frame")
    let edge: SIMD2<Float> = scene.height > scene.width ? SIMD2(2, Float(scene.height) / 2) : SIMD2(Float(scene.width) / 2, 2)
    let r = red.pixel(edge.x, edge.y), b = blue.pixel(edge.x, edge.y)
    check(r.x - b.x > 0.1 && b.z - r.z > 0.1, "\(scene.name): changed whole-UI frame changes edge colors without Carousel")
    let varied = try render(scene) { bandColor(scene, $0) }
    validate(varied, name: "\(scene.name) bands")
    for channel in 0..<3 {
        let fraction = Float(channel * 2 + 1) / 6
        let p = scene.height > scene.width ? varied.pixel(edge.x, Float(scene.height) * fraction) : varied.pixel(Float(scene.width) * fraction, edge.y)
        check(p[channel] - max(p[(channel + 1) % 3], p[(channel + 2) % 3]) > 0.05, "\(scene.name): band \(channel) preserves scene coordinate and color")
    }
    let dark = try render(scene, dark: true) { bandColor(scene, $0) }
    validate(dark, name: "\(scene.name) dark")
    let opaque = try render(scene, reduce: true) { bandColor(scene, $0) }
    validate(opaque, name: "\(scene.name) reduced transparency")
    check(opaque.values.enumerated().allSatisfy { index, pixel in distance(opaque, x: index % opaque.width, y: index / opaque.width) > -0.25001 || pixel.w == 1 }, "\(scene.name): every fully covered Reduce Transparency pixel opaque")

}
var clipped = vertical
clipped.name = "nonzero-visible-origin"
clipped.visible = SIMD4(20.3, 100.3, 180.3, 280.3)
func visibleColor(_ p: SIMD2<Float>, hidden: SIMD4<Float>) -> SIMD4<Float> {
    let rect = clipped.visibleRect
    return p.x >= rect.x && p.y >= rect.y && p.x <= rect.z && p.y <= rect.w ? colors[1] : hidden
}
let clipRed = try render(clipped) { visibleColor($0, hidden: colors[0]) }
let clipBlue = try render(clipped) { visibleColor($0, hidden: colors[2]) }
validate(clipRed, name: "clipped full-size GPU scene")
check(difference(clipRed, clipBlue) == 0, "visibleRect: changing every hidden texel produces exactly identical output")
let clippedEdge = clipRed.pixel(2, 103)
check(clippedEdge.y - max(clippedEdge.x, clippedEdge.z) > 0.1, "visibleRect: nonzero origin preserves full-source UVs and visible green")
var far = vertical
far.origin.x = 480
let farRed = try render(far) { _ in colors[0] }
let farBlue = try render(far) { _ in colors[2] }
validate(farRed, name: "source beyond sampling reach")
check(difference(farRed, farBlue) == 0, "far scene: cannot tint the capsule")
var absent = vertical
absent.origin = .zero
absent.sourceSize = SIMD2(1, 1)
absent.visible = .zero
let noSource = try render(absent, onePixelSource: true) { _ in .zero }
validate(noSource, name: "no-source transparent 1x1")
check(difference(noSource, farRed) == 0, "no-source 1x1 produces the same neutral capsule as an unreachable scene")
var hidden = vertical
hidden.visible = SIMD4(120, 160, 120, 160)
let hiddenFrame = try render(hidden) { _ in colors[0] }
check(difference(hiddenFrame, noSource) == 0, "empty visible rectangle contributes no scene pixels")
let fullRed = try render(vertical) { _ in colors[0] }
let quarterRed = try render(vertical) { _ in SIMD4(0.25, 0, 0, 0.25) }
let fullDifference = fullRed.pixel(2, 103).x - noSource.pixel(2, 103).x
let quarterDifference = quarterRed.pixel(2, 103).x - noSource.pixel(2, 103).x
check(quarterDifference > 0 && quarterDifference < fullDifference * 0.4, "premultiplied translucent scene pixels attenuate the reflected color")
validate(quarterRed, name: "quarter-alpha GPU scene")
for scene in [vertical, horizontal] {
    for dark in [false, true] {
        let appearance = dark ? "dark" : "light"
        var lightingOnly = scene
        lightingOnly.visible = .zero
        let lighting = try render(lightingOnly, dark: dark) { _ in .zero }
        validate(lighting, name: "\(scene.name) \(appearance) lighting only")
        let inside = lighting.values.enumerated().filter {
            distance(lighting, x: $0.offset % lighting.width, y: $0.offset / lighting.width) < -12.01
        }
        let expectedAlpha: Float = 0.88
        check(!inside.isEmpty && inside.allSatisfy { abs($0.element.w - expectedAlpha) < 1e-6 },
              "\(scene.name) \(appearance): no-source interior retains custom neutral thickness")
        check(lighting.values.contains { $0.x - $0.z > 0.005 },
              "\(scene.name) \(appearance): warm sharp/soft highlights survive without a scene")
        check(lighting.values.contains { $0.z - $0.x > 0.002 },
              "\(scene.name) \(appearance): cool opposing highlights survive without a scene")
        check(lighting.values.contains { $0.w - max($0.x, max($0.y, $0.z)) > 0.003 },
              "\(scene.name) \(appearance): rim keeps absorption beyond its emitted highlight")
        let middle = Float(scene.height) / 2
        let sharp = lighting.pixel(0.25, middle)
        let soft = lighting.pixel(1.25, middle)
        let inner = lighting.pixel(3.25, middle)
        check(sharp.x > soft.x && soft.x > inner.x,
              "\(scene.name) \(appearance): sharp contour fades through a softer interior glow")
        let colored = try render(scene, dark: dark) { _ in colors[0] }
        let coloredCenter = colored.pixel(Float(scene.width) / 2, Float(scene.height) / 2)
        let neutralCenter = lighting.pixel(Float(scene.width) / 2, Float(scene.height) / 2)
        check(coloredCenter.x > neutralCenter.x && abs(coloredCenter.w - neutralCenter.w) < 1e-6,
              "\(scene.name) \(appearance): nearby colors wash the face without changing its uniform opacity")
        let opaqueRed = try render(scene, reduce: true, dark: dark) { _ in colors[0] }
        let opaqueBlue = try render(scene, reduce: true, dark: dark) { _ in colors[2] }
        validate(opaqueRed, name: "\(scene.name) \(appearance) reduced transparency")
        let center = opaqueRed.pixel(Float(scene.width) / 2, Float(scene.height) / 2)
        check(center.w == 1 && abs(center.x - (dark ? 0.018 : 0.90)) < 1e-5,
              "\(scene.name) \(appearance): Reduce Transparency retains opaque appearance-appropriate fill")
        check(difference(opaqueRed, opaqueBlue) == 0,
              "\(scene.name) \(appearance): Reduce Transparency suppresses source colors")

    }
}
func renderFeeds(_ scene: Scene = vertical, previous: MTLTexture, current: MTLTexture, live: MTLTexture, interpolation: Float = 1, hasScene: Bool = true, previousRect: SIMD4<Float>? = nil, sceneRect: SIMD4<Float>? = nil, cropOrigin: SIMD2<Float> = .zero, reduce: Bool = false, overrides: ((inout Uniforms) -> Void)? = nil) throws -> Result {
    let fullRect = SIMD4(cropOrigin.x, cropOrigin.y, Float(scene.sourceSize.x), Float(scene.sourceSize.y))
    var uniforms = Uniforms(
        geometry: SIMD4(Float(scene.width), Float(scene.height), 2, 0),
        capture: SIMD4(scene.origin.x, scene.origin.y, Float(scene.sourceSize.x), Float(scene.sourceSize.y)),
        material: SIMD4(-25 * .pi / 180, 1.5, 96, reduce ? 1 : 0),
        visibleRect: scene.visibleRect,
        previousCapture: previousRect ?? fullRect,
        sceneRect: sceneRect ?? fullRect,
        feed: SIMD4(cropOrigin.x, cropOrigin.y, interpolation, hasScene ? 1 : 0)
    )
    uniforms.apply(.defaults)
    overrides?(&uniforms)
    return try execute(target(scene.width * 2, scene.height * 2), previous, opticsPipeline, uniforms: uniforms, current: current, scene: live)
}
let redTexture = texture(vertical.sourceSize) { _ in colors[0] }
let blueTexture = texture(vertical.sourceSize) { _ in colors[2] }
let greenTexture = texture(vertical.sourceSize) { _ in colors[1] }
let clearTexture = texture(SIMD2(1, 1)) { _ in .zero }
let underBarTexture = texture(vertical.sourceSize, gpuPremultiplied: true) { point in
    let p = point - vertical.origin
    return p.x >= 0 && p.x <= Float(vertical.width) && p.y >= 0 && p.y <= Float(vertical.height) ? colors[1] : .zero
}
let underBar = try renderFeeds(previous: clearTexture, current: clearTexture, live: underBarTexture)
let underPixel = underBar.pixel(6, 103), absentPixel = noSource.pixel(6, 103)
check(underPixel.y - absentPixel.y > 0.005 && underPixel.x <= absentPixel.x,
      "valid direct Carousel pixels underneath the capsule contribute independently of UI exclusion")
let interpolationStart = try renderFeeds(previous: redTexture, current: blueTexture, live: clearTexture, interpolation: 0, hasScene: false)
let interpolationMid = try renderFeeds(previous: redTexture, current: blueTexture, live: clearTexture, interpolation: 0.5, hasScene: false)
let interpolationEnd = try renderFeeds(previous: redTexture, current: blueTexture, live: clearTexture, interpolation: 1, hasScene: false)
let startPixel = interpolationStart.pixel(2, 103), middlePixel = interpolationMid.pixel(2, 103), endPixel = interpolationEnd.pixel(2, 103)
check(startPixel.x > middlePixel.x && middlePixel.x > endPixel.x && startPixel.z < middlePixel.z && middlePixel.z < endPixel.z, "previous/current UI colors interpolate smoothly on the GPU without Carousel")
validate(interpolationMid, name: "interpolated UI frame")
let liveFull = try renderFeeds(previous: redTexture, current: redTexture, live: greenTexture)
let uiGreen = try renderFeeds(previous: greenTexture, current: greenTexture, live: clearTexture, hasScene: false)
check(difference(liveFull, uiGreen) < 1e-5, "opaque direct Carousel replaces stale UI pixels in the matching window region")
let sceneFar = try renderFeeds(previous: redTexture, current: redTexture, live: greenTexture, sceneRect: SIMD4(700, 700, 236, 398))
check(difference(sceneFar, interpolationStart) < 1e-5, "Carousel outside the sampling region cannot replace the whole UI")
let partialLive = try renderFeeds(previous: redTexture, current: redTexture, live: greenTexture, sceneRect: SIMD4(0, 0, 236, 170))
let upper = partialLive.pixel(2, 25), lower = partialLive.pixel(2, 181)
check(upper.y > upper.x && lower.x > lower.y, "UI and direct Carousel contribute simultaneously at their own window coordinates")
let halfGreenTexture = texture(vertical.sourceSize, gpuPremultiplied: true) { _ in SIMD4(0, 0.5, 0, 0.5) }
let liveHalf = try renderFeeds(previous: redTexture, current: redTexture, live: halfGreenTexture)
let halfPixel = liveHalf.pixel(2, 103)
check(halfPixel.x > halfPixel.z + 0.1 && halfPixel.y > halfPixel.z + 0.1, "translucent Carousel source-overs its premultiplied colors onto the UI")
validate(liveHalf, name: "combined translucent feeds")
let noSceneFlag = try renderFeeds(previous: redTexture, current: redTexture, live: greenTexture, hasScene: false)
check(difference(noSceneFlag, interpolationStart) < 1e-5, "disconnecting Carousel preserves whole-UI reflections")
let shiftedCrops = try renderFeeds(previous: redTexture, current: blueTexture, live: clearTexture, interpolation: 0, hasScene: false, previousRect: SIMD4(100, 80, 236, 398), cropOrigin: SIMD2(100, 80))
check(difference(shiftedCrops, interpolationStart) < 1e-5, "UI interpolation maps both crop origins through window coordinates")
let shiftedScene = try renderFeeds(previous: redTexture, current: redTexture, live: greenTexture, sceneRect: SIMD4(100, 80, 236, 398), cropOrigin: SIMD2(100, 80))
check(difference(shiftedScene, liveFull) < 1e-5, "direct Carousel maps nonzero window origins correctly")
let movingPreviousRect = SIMD4<Float>(60, 40, 300, 450)
let previousBands = texture(SIMD2(300, 450)) { point in bandColor(vertical, point + SIMD2(60, 40) - SIMD2(100, 80)) }
let shiftedBands = try renderFeeds(previous: previousBands, current: blueTexture, live: clearTexture, interpolation: 0, hasScene: false, previousRect: movingPreviousRect, cropOrigin: SIMD2(100, 80))
for channel in 0..<3 {
    let value = shiftedBands.pixel(2, Float(vertical.height) * Float(channel * 2 + 1) / 6)
    check(value[channel] > value[(channel + 1) % 3] + 0.03 && value[channel] > value[(channel + 2) % 3] + 0.03, "moving crop: previous UI band \(channel) remains in window coordinates")
}
let maskedUI = texture(vertical.sourceSize) { p in
    let local = p - vertical.origin
    if local.x >= -6 && local.x <= Float(vertical.width) + 6 && local.y >= -6 && local.y <= Float(vertical.height) + 6 { return .zero }
    return colors[2]
}
let maskedFrame = try renderFeeds(previous: maskedUI, current: maskedUI, live: clearTexture, hasScene: false)
let maskedRim = maskedFrame.pixel(2, 103)
check(maskedRim.z > max(maskedRim.x, maskedRim.y) + 0.25,
      "whole-UI neighbors strongly tint the rim when the entire bar plus six points is excluded")
check(difference(maskedFrame, interpolationEnd) < 1e-6,
      "changing excluded UI bar pixels cannot feed back into either the rim or face wash")
let opaqueFeeds = try renderFeeds(previous: redTexture, current: blueTexture, live: greenTexture, reduce: true)
let opaqueAbsent = try renderFeeds(previous: clearTexture, current: clearTexture, live: clearTexture, hasScene: false, reduce: true)
check(difference(opaqueFeeds, opaqueAbsent) == 0, "Reduce Transparency suppresses both UI and Carousel feeds")
let copyInput = texture(SIMD2(200, 100)) { point in point.x < 100 ? colors[0] : colors[2] }
let copied = try execute(target(80, 80), copyInput, copyPipeline, uniforms: nil, copyRect: SIMD4(0.5, 0, 0.5, 1))
check(copied.values.allSatisfy { abs($0.z - 1) < 1e-5 && $0.x < 1e-5 && $0.y < 1e-5 && $0.w == 1 }, "GPU copy samples only the normalized producer crop")
let copyAlphaInput = texture(SIMD2(100, 100), gpuPremultiplied: true) { _ in SIMD4(0.25, 0, 0, 0.25) }
let copiedAlpha = try execute(target(80, 80), copyAlphaInput, copyPipeline, uniforms: nil, copyRect: SIMD4(0, 0, 1, 1))
check(copiedAlpha.values.allSatisfy { abs($0.x - 0.25) < 0.005 && abs($0.w - 0.25) < 0.005 && $0.y == 0 && $0.z == 0 }, "GPU copy preserves producer premultiplication")
let fractionalCopyRect = SIMD4<Float>(0.203, 0.153, 0.404, 0.504)
func croppedProducer(_ hidden: SIMD4<Float>) -> MTLTexture {
    texture(SIMD2(100, 100)) { point in
        point.x >= 20.3 && point.x <= 60.7 && point.y >= 15.3 && point.y <= 65.7 ? colors[1] : hidden
    }
}
let copyRedOutside = try execute(target(161, 201), croppedProducer(colors[0]), copyPipeline, uniforms: nil, copyRect: fractionalCopyRect)
let copyBlueOutside = try execute(target(161, 201), croppedProducer(colors[2]), copyPipeline, uniforms: nil, copyRect: fractionalCopyRect)
check(difference(copyRedOutside, copyBlueOutside) == 0, "fractional producer crop never samples a hidden neighboring texel, even when enlarged")
let emptyCopy = try execute(target(10, 10), copyInput, copyPipeline, uniforms: nil, copyRect: SIMD4(0.5, 0.5, 0, 0))
check(emptyCopy.values.allSatisfy { $0 == .zero }, "empty producer crop stays transparent")

// Verify the actual CAMetalLayer pixel format, including the GPU's automatic
// sRGB write conversion. Float-target tests alone cannot catch encoded RGB > A.
struct RawDrawable {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    func pixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
        let offset = (y * width + x) * 4
        return SIMD4(Float(bytes[offset + 2]), Float(bytes[offset + 1]),
                     Float(bytes[offset]), Float(bytes[offset + 3])) / 255
    }
}
func renderDrawable(dark: Bool, reduce: Bool = false, ui: MTLTexture = clearTexture,
                    hasUI: Bool = false, live: MTLTexture = clearTexture, hasLive: Bool = false,
                    overrides: ((inout Uniforms) -> Void)? = nil) throws -> RawDrawable {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
        width: vertical.width * 2, height: vertical.height * 2, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    let output = device.makeTexture(descriptor: descriptor)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    var uniforms = Uniforms(
        geometry: SIMD4(Float(vertical.width), Float(vertical.height), 2, dark ? 1 : 0),
        capture: SIMD4(vertical.origin.x, vertical.origin.y, Float(vertical.sourceSize.x), Float(vertical.sourceSize.y)),
        material: SIMD4(-25 * .pi / 180, 1.5, 96, reduce ? 1 : 0),
        visibleRect: hasUI ? vertical.visibleRect : .zero,
        previousCapture: SIMD4(0, 0, Float(vertical.sourceSize.x), Float(vertical.sourceSize.y)),
        sceneRect: SIMD4(0, 0, Float(vertical.sourceSize.x), Float(vertical.sourceSize.y)),
        feed: SIMD4(0, 0, 1, hasLive ? 1 : 0))
    uniforms.apply(.defaults)
    overrides?(&uniforms)
    let command = queue.makeCommandBuffer()!
    let preparedUI = prepareUI(ui, command: command)
    prepareWash(uniforms, previous: preparedUI, current: preparedUI, scene: live, command: command)
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(drawablePipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.setFragmentTexture(preparedUI, index: 0)
    encoder.setFragmentTexture(preparedUI, index: 1)
    encoder.setFragmentTexture(live, index: 2)
    encoder.setFragmentTexture(washTexture, index: 3)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    if let error = command.error { throw error }
    frameCount += 1
    var bytes = [UInt8](repeating: 0, count: output.width * output.height * 4)
    output.getBytes(&bytes, bytesPerRow: output.width * 4,
                   from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0)
    return RawDrawable(width: output.width, height: output.height, bytes: bytes)
}
func validEncodedPremultiplication(_ image: RawDrawable) -> Bool {
    stride(from: 0, to: image.bytes.count, by: 4).allSatisfy { offset in
        let alpha = Int(image.bytes[offset + 3])
        return (0..<3).allSatisfy { Int(image.bytes[offset + $0]) <= alpha + 1 }
    }
}
func compositeInCoreGraphics(_ image: RawDrawable, over gray: CGFloat) -> SIMD4<Float> {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let flags = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    let provider = CGDataProvider(data: Data(image.bytes) as CFData)!
    let source = CGImage(width: image.width, height: image.height, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: flags), provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
    let context = CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: flags)!
    context.setFillColor(CGColor(colorSpace: space, components: [gray, gray, gray, 1])!)
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.fill(rect)
    context.draw(source, in: rect)
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let offset = (image.height / 2 * image.width + image.width / 2) * 4
    return SIMD4(Float(bytes[offset + 2]), Float(bytes[offset + 1]),
                 Float(bytes[offset]), Float(bytes[offset + 3])) / 255
}
for dark in [false, true] {
    let image = try renderDrawable(dark: dark)
    let center = image.pixel(image.width / 2, image.height / 2)
    let alpha: Float = 0.88
    let encoded = srgb(dark ? 0.018 : 0.90) * alpha
    check(validEncodedPremultiplication(image), "actual BGRA8_sRGB \(dark ? "dark" : "light") drawable: every encoded RGB channel is bounded by alpha")
    check(abs(center.x - encoded) < 0.005 && abs(center.w - alpha) < 0.005,
          "actual BGRA8_sRGB \(dark ? "dark" : "light") drawable: center stores encoded straight color times alpha")
    let composite = compositeInCoreGraphics(image, over: 0.8)
    let expected = encoded + 0.8 * (1 - alpha)
    check(abs(composite.x - expected) < 0.012 && composite.x < 0.95 && composite.w == 1,
          "Core Graphics source-over \(dark ? "dark" : "light") drawable: translucent fill does not clip to pure white")
    let opaque = try renderDrawable(dark: dark, reduce: true)
    let opaqueCenter = opaque.pixel(opaque.width / 2, opaque.height / 2)
    check(opaqueCenter.w == 1 && abs(opaqueCenter.x - srgb(dark ? 0.018 : 0.90)) < 0.005,
          "actual BGRA8_sRGB \(dark ? "dark" : "light") Reduce Transparency output remains opaque")
}
// The actual displayed content contributes through Core Animation as well as
// through the sampled body texture. Exercise both paths with extreme black /
// white text contrast so a superficially opaque-looking shader cannot pass
// while reintroducing the same sharp background detail through its own sample.
let blackTextBackdrop = texture(vertical.sourceSize) { _ in SIMD4(0, 0, 0, 1) }
let whiteTextBackdrop = texture(vertical.sourceSize) { _ in SIMD4(1, 1, 1, 1) }
for dark in [false, true] {
    let blackLayer = try renderDrawable(dark: dark, ui: blackTextBackdrop, hasUI: true)
    let whiteLayer = try renderDrawable(dark: dark, ui: whiteTextBackdrop, hasUI: true)
    let blackCenter = compositeInCoreGraphics(blackLayer, over: 0).x
    let whiteCenter = compositeInCoreGraphics(whiteLayer, over: 1).x
    let centerContrast = whiteCenter - blackCenter
    let blackRim = blackLayer.pixel(4, blackLayer.height / 2)
    let whiteRim = whiteLayer.pixel(4, whiteLayer.height / 2)
    let rimContrast = whiteRim.x + 1 - whiteRim.w - blackRim.x
    check(centerContrast >= 0 && centerContrast < 0.22,
          "\(dark ? "dark" : "light") labels: center suppresses sampled and transmitted background text contrast")
    check(rimContrast > centerContrast * 1.3,
          "\(dark ? "dark" : "light") material: stronger rim color retains uniform body opacity (center contrast \(centerContrast), rim \(rimContrast))")
}
let mixedDrawable = try renderDrawable(dark: false, ui: blueTexture, hasUI: true,
                                       live: halfGreenTexture, hasLive: true)
check(validEncodedPremultiplication(mixedDrawable), "actual BGRA8_sRGB drawable: combined UI and translucent Carousel stay encoded-premultiplied")
let quarterUI = texture(vertical.sourceSize) { _ in SIMD4(0.25, 0, 0, 0.25) }
let quarterScene = texture(vertical.sourceSize, gpuPremultiplied: true) { _ in SIMD4(0.25, 0, 0, 0.25) }
let uiAlphaResult = try renderFeeds(previous: quarterUI, current: quarterUI, live: clearTexture, hasScene: false)
let sceneAlphaResult = try renderFeeds(previous: clearTexture, current: clearTexture, live: quarterScene)
check(difference(uiAlphaResult, sceneAlphaResult) < 0.006,
      "Core Graphics encoded-premultiplied UI and GPU linear-premultiplied scene produce the same fractional-alpha optics")
let edgeUI = texture(vertical.sourceSize) { point in
    point.x < 119.3 ? SIMD4(0.25, 0.1, 0.04, 1) : .zero
}
let edgeScene = texture(vertical.sourceSize, gpuPremultiplied: true) { point in
    point.x < 119.3 ? SIMD4(0.25, 0.1, 0.04, 1) : .zero
}
// Compare the prepared source fields before UI's intentional feedback hole is
// applied. That hole is not present in a direct scene, so a clear/colored edge
// crossing the capsule is intentionally different in the final optical pass.
let edgePrepareCommand = queue.makeCommandBuffer()!
let preparedEdge = prepareUI(edgeUI, command: edgePrepareCommand)
edgePrepareCommand.commit()
edgePrepareCommand.waitUntilCompleted()
if let error = edgePrepareCommand.error { throw error }
let uiEdgeResult = try execute(target(321, 501), preparedEdge, copyPipeline,
                              uniforms: nil, copyRect: SIMD4(0, 0, 1, 1))
let sceneEdgeResult = try execute(target(321, 501), edgeScene, copyPipeline,
                                 uniforms: nil, copyRect: SIMD4(0, 0, 1, 1))
check(difference(uiEdgeResult, sceneEdgeResult) < 0.006,
      "prepared linear UI preserves dim premultiplied color at bilinear clear-mask edges")
let tinyRawDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
    width: 2, height: 2, mipmapped: false)
tinyRawDescriptor.storageMode = .shared
tinyRawDescriptor.usage = .shaderRead
let tinyRaw = device.makeTexture(descriptor: tinyRawDescriptor)!
let tinyBytes: [UInt8] = [0, 0, 128, 128, 64, 0, 0, 128,
                        0, 64, 0, 255, 0, 0, 0, 0]
tinyRaw.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                withBytes: tinyBytes, bytesPerRow: 8)
let prepareCommand = queue.makeCommandBuffer()!
let preparedTiny = prepareUI(tinyRaw, command: prepareCommand)
prepareCommand.commit()
prepareCommand.waitUntilCompleted()
if let error = prepareCommand.error { throw error }
frameCount += 1
var tinyHalf = [UInt16](repeating: 0, count: 16)
preparedTiny.getBytes(&tinyHalf, bytesPerRow: 16,
                     from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
let tinyLinear = tinyHalf.map { Float(Float16(bitPattern: $0)) }
check(abs(tinyLinear[0] - 128.0 / 255) < 0.001 && abs(tinyLinear[3] - 128.0 / 255) < 0.001,
      "prepare UI pass: translucent red stores linear-premultiplied RGBA16Float")
check(abs(tinyLinear[6] - linear(0.5) * (128.0 / 255)) < 0.001 && tinyLinear[4] == 0,
      "prepare UI pass: fractional blue unpremultiplies before decoding once")
check(abs(tinyLinear[9] - linear(64.0 / 255)) < 0.001 && tinyLinear[11] == 1,
      "prepare UI pass: pixel rows retain top-left orientation")
check(tinyLinear[12..<16].allSatisfy { $0 == 0 }, "prepare UI pass: cleared feedback hole stays exactly transparent")

// Material shape and modes: the face is a slightly transparent solid, not a
// clear outline around an unrelated opaque fill. These fixtures disable only
// additive lighting so every fully covered pixel has the same declared alpha.
check(MemoryLayout<Uniforms>.stride == 160, "Swift/Metal uniform contract is exactly ten SIMD4 values")
for scene in [vertical, horizontal] {
    for mode in TabBarReflectionSettings.Mode.allCases {
        var tuning = TabBarReflectionSettings.defaults
        tuning.mode = mode
        tuning.reflectionStrength = 0
        tuning.sharpHighlight = 0
        tuning.softGlow = 0
        tuning.edgeDarkening = 0
        let material = try render(scene, overrides: { $0.apply(tuning) }) { _ in colors[2] }
        let solidPixels = material.values.enumerated().filter {
            distance(material, x: $0.offset % material.width, y: $0.offset / material.width) < -0.26
        }
        check(solidPixels.allSatisfy { abs($0.element.w - 0.88) < 1e-6 },
              "\(scene.name) \(mode.rawValue): uniform 88% opacity reaches the rim and center")
        let center = material.pixel(Float(scene.width) / 2, Float(scene.height) / 2)
        if mode == .mostlyEdges {
            check(abs(center.x - center.z) < 1e-6 && abs(center.x - 0.90 * 0.88) < 1e-5,
                  "\(scene.name): edge-only mode leaves a neutral face")
        } else {
            check(center.z > center.x + 0.10,
                  "\(scene.name): Face + Edges adds a soft nearby-color wash to the same solid face")
        }
    }
    let colorBands = try render(scene, dark: true) { bandColor(scene, $0) }
    for channel in 0..<3 {
        let fraction = Float(channel * 2 + 1) / 6
        let point = scene.height > scene.width
            ? colorBands.pixel(Float(scene.width) / 2, Float(scene.height) * fraction)
            : colorBands.pixel(Float(scene.width) * fraction, Float(scene.height) / 2)
        check(point[channel] > max(point[(channel + 1) % 3], point[(channel + 2) % 3]) + 0.01,
              "\(scene.name): 64-texel face field keeps longitudinal color band \(channel)")
    }
}

// The outward side of a screen-edge capsule must retain nearby inward colors.
// This specifically fails the previous normalization by all requested rays.
var duoEdge = vertical
duoEdge.origin.x = Float(duoEdge.sourceSize.x - duoEdge.width - 8)
let duoBlue = try render(duoEdge) { _ in colors[2] }
let outward = duoBlue.pixel(Float(duoEdge.width) - 2, 103)
check(outward.z - max(outward.x, outward.y) > 0.25,
      "Duo outward rim remains strongly blue when outward sampling rays leave the screen")
var bottomEdge = horizontal
bottomEdge.origin.y = Float(bottomEdge.sourceSize.y - bottomEdge.height - 8)
let bottomGreen = try render(bottomEdge) { _ in colors[1] }
let bottom = bottomGreen.pixel(180, Float(bottomEdge.height) - 2)
check(bottom.y - max(bottom.x, bottom.z) > 0.25,
      "bottom phone rim remains strongly green when lower sampling rays leave the screen")

// Boundary onset: translate a tiny available source footprint through the
// filter. Eligibility comes from geometry, never an alpha threshold. Uniform
// translucent content remains proportional even at the screen edge.
let duoQuarter = try render(duoEdge) { _ in SIMD4(0, 0, 0.25, 0.25) }
let quarterOutward = duoQuarter.pixel(Float(duoEdge.width) - 2, 103)
let fullChroma = outward.z - outward.x
let quarterChroma = quarterOutward.z - quarterOutward.x
check(quarterChroma > 0 && quarterChroma < fullChroma * 0.4,
      "screen-edge normalization preserves actual fractional source alpha")
var previousBoundary: SIMD4<Float>?
var boundaryPeak: Float = 0
var boundaryFirst: SIMD4<Float>?
var boundaryLast: SIMD4<Float> = .zero
for step in 0...250 {
    var boundary = vertical
    boundary.origin.x = 280 - Float(step) * 0.1
    let frame = try render(boundary, dark: true, overrides: { $0.surface.z = 0 }) { _ in colors[2] }
    let pixel = frame.pixel(2, 103)
    if let previousBoundary {
        let delta = abs(pixel.z - previousBoundary.z)
        boundaryPeak = max(boundaryPeak, delta)
    } else { boundaryFirst = pixel }
    previousBoundary = pixel
    boundaryLast = pixel
}
check(boundaryLast.z - boundaryFirst!.z > 0.15 && boundaryPeak < 0.12,
      "source footprint enters smoothly rather than popping to full reflection (peak step \(boundaryPeak))")

// Every public slider affects its expected mode and remains finite at both
// endpoints. Use varied, unsaturated colors rather than pure RGB that would
// hide saturation, reach and softness changes through clipping.
func tuningColor(_ p: SIMD2<Float>) -> SIMD4<Float> {
    let x = p.x / Float(vertical.sourceSize.x), y = p.y / Float(vertical.sourceSize.y)
    return SIMD4(0.12 + 0.35 * y, 0.13 + 0.35 * x, 0.55 - 0.3 * y, 1)
}
for mode in TabBarReflectionSettings.Mode.allCases {
    for parameter in TabBarReflectionSettings.Parameter.allCases {
        var lower = TabBarReflectionSettings.defaults
        lower.mode = mode
        lower[keyPath: parameter.keyPath] = parameter.range.lowerBound
        var upper = lower
        upper[keyPath: parameter.keyPath] = parameter == .lightDirectionDegrees
            ? 90 : parameter.range.upperBound // -180 and +180 are the same direction.
        let low = try render(vertical, dark: true, overrides: { $0.apply(lower) }, color: tuningColor)
        let high = try render(vertical, dark: true, overrides: { $0.apply(upper) }, color: tuningColor)
        validate(low, name: "\(mode.rawValue) \(parameter.rawValue) minimum")
        validate(high, name: "\(mode.rawValue) \(parameter.rawValue) maximum")
        let delta = difference(low, high)
        if mode == .mostlyEdges && parameter == .faceWash {
            check(delta == 0, "edge-only mode ignores stored wash strength without changing shared values")
        } else {
            check(delta > 1e-5, "\(mode.rawValue): \(parameter.rawValue) reaches the shader and changes its material")
        }
    }
}
for mode in TabBarReflectionSettings.Mode.allCases {
    for dark in [false, true] {
        for maximum in [false, true] {
            var extremes = TabBarReflectionSettings.defaults
            extremes.mode = mode
            for parameter in TabBarReflectionSettings.Parameter.allCases {
                extremes[keyPath: parameter.keyPath] = maximum ? parameter.range.upperBound : parameter.range.lowerBound
            }
            let drawable = try renderDrawable(dark: dark, ui: blueTexture, hasUI: true,
                                               live: halfGreenTexture, hasLive: true,
                                               overrides: { $0.apply(extremes) })
            check(validEncodedPremultiplication(drawable),
                  "\(mode.rawValue) \(dark ? "dark" : "light") combined slider \(maximum ? "maxima" : "minima") remain valid encoded-premultiplied bytes")
        }
    }
}
let washCount = washPasses
_ = try render(vertical, overrides: { $0.surface.z = 0 }) { _ in colors[0] }
_ = try render(vertical, overrides: { $0.surface.y = 0 }) { _ in colors[0] }
_ = try render(vertical, reduce: true) { _ in colors[0] }
check(washPasses == washCount, "edge-only, zero wash and Reduce Transparency skip the field pass")
_ = try render(vertical) { _ in colors[0] }
check(washPasses == washCount + 1, "Face + Edges encodes one tiny field pass, independent of capsule pixel count")
print("SUCCESS: \(checks) checks passed, \(frameCount) optics/copy frames on \(device.name), uniforms=\(MemoryLayout<Uniforms>.stride) bytes, UI preparation passes=\(preparationPasses), wash passes=\(washPasses). Exact production shader; no simulator/UI launched.")
