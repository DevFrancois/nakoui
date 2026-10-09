import SwiftUI

/// Fills its bounds with four soft Gaussian lights along the top edge and four
/// more along the bottom, drawn by `AmbientGradientShader.metal`.
/// Ported from ZoomInUIKit's `GridGradientSurface`.
struct AmbientGradientSurface: View {
    /// Lights along the top edge, left to right: four.
    let topLights: [SIMD3<Float>]
    /// The color the lights fade into.
    let background: SIMD3<Float>
    /// The fraction of the height the top lights spread over, anchored at the top.
    let verticalCoverage: CGFloat
    /// Lights along the bottom edge, left to right: four.
    let bottomLights: [SIMD3<Float>]
    /// Like `verticalCoverage`, for the bottom lights, anchored at the bottom.
    let bottomCoverage: CGFloat

    @State private var size = CGSize.zero

    var body: some View {
        Rectangle()
            .fill(shader)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
    }

    private var shader: Shader {
        let height = max(Float(size.height), 1)
        // Compress only Y, anchored at each edge, so the lights cover part of the height.
        let inverseSize = Shader.Argument.float2(1 / max(Float(size.width), 1), 1 / height / Float(verticalCoverage))
        let bottomInverseHeight = Shader.Argument.float(1 / height / Float(bottomCoverage))
        // Each light's distance from its edge, and how fast the lights fade
        // with distance and build up where they overlap.
        let centerY = Shader.Argument.float4(-0.015, 0.13, -0.05, -0.03)
        let falloffScale = Shader.Argument.float(-1.8)
        let coverageScale = Shader.Argument.float(1.5)

        // Uniform work happens once per frame rather than once per fragment.
        return ShaderFunction(library: .default, name: "ambientLightingEdges")(
            inverseSize,
            bottomInverseHeight,
            .float(height),
            centerY,
            falloffScale,
            coverageScale,
            argument(topLights[0]),
            argument(topLights[1]),
            argument(topLights[2]),
            argument(topLights[3]),
            argument(bottomLights[0]),
            argument(bottomLights[1]),
            argument(bottomLights[2]),
            argument(bottomLights[3]),
            argument(background)
        )
    }

    private func argument(_ color: SIMD3<Float>) -> Shader.Argument {
        .float3(color.x, color.y, color.z)
    }
}
