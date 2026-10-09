import SwiftUI

/// Fills its bounds with four soft Gaussian lights at the top edge, and
/// optionally four more along the bottom, drawn by `AmbientGradientShader.metal`.
/// Ported from ZoomInUIKit's `GridGradientSurface`.
struct AmbientGradientSurface: View {
    let frame: AmbientGradientFrame
    /// The color the lights fade into.
    let background: SIMD3<Float>
    /// The fraction of the height the lights spread over, anchored at the top.
    let verticalCoverage: CGFloat
    /// Lights along the bottom edge, left to right: four, or none.
    var bottomLights: [SIMD3<Float>] = []
    /// Like `verticalCoverage`, for the bottom lights, anchored at the bottom.
    var bottomCoverage: CGFloat = 1

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
        let bloom = min(max(frame.bloom, 0), 1)
        let spread = 1 + bloom * 0.12
        let colors = frame.colors
        let height = max(Float(size.height), 1)
        // Compress only Y, anchored at the top, so the lights cover the top part.
        let inverseSize = Shader.Argument.float2(1 / max(Float(size.width), 1), 1 / height / Float(verticalCoverage))
        let centerY = Shader.Argument.float4(-0.015, 0.13, -0.05, -0.03)
        let falloffScale = Shader.Argument.float(-1.8 / (spread * spread))
        let coverageScale = Shader.Argument.float(1.5 + bloom * 0.12)

        // Uniform work happens once per frame rather than once per fragment.
        if bottomLights.count == 4 {
            return ShaderFunction(library: .default, name: "ambientLightingEdges")(
                inverseSize,
                .float(1 / height / Float(bottomCoverage)),
                .float(height),
                centerY,
                falloffScale,
                coverageScale,
                argument(colors[0]),
                argument(colors[1]),
                argument(colors[2]),
                argument(colors[3]),
                argument(bottomLights[0]),
                argument(bottomLights[1]),
                argument(bottomLights[2]),
                argument(bottomLights[3]),
                argument(background)
            )
        }

        let isDark = background.max() < 0.5
        let hasBoundedColors = colors.allSatisfy { color in
            color.x >= 0 && color.x <= 1
                && color.y >= 0 && color.y <= 1
                && color.z >= 0 && color.z <= 1
        }
        // Dark fades benefit from float weights in the very soft Gaussian tails.
        let function = ShaderFunction(
            library: .default,
            name: hasBoundedColors && !isDark ? "ambientLightingFast" : "ambientLighting"
        )
        return function(
            inverseSize,
            centerY,
            falloffScale,
            coverageScale,
            .float3(0, 0, 0),
            argument(colors[0]),
            argument(colors[1]),
            argument(colors[2]),
            argument(colors[3]),
            argument(background)
        )
    }

    private func argument(_ color: SIMD3<Float>) -> Shader.Argument {
        .float3(color.x, color.y, color.z)
    }
}
