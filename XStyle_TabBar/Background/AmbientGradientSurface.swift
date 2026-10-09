import SwiftUI

/// Fills its bounds with four soft Gaussian lights at the top edge, drawn by
/// `AmbientGradientShader.metal`. Ported from ZoomInUIKit's `GridGradientSurface`.
struct AmbientGradientSurface: View {
    let frame: AmbientGradientFrame
    /// The color the lights fade into.
    let background: SIMD3<Float>
    /// The fraction of the height the lights spread over, anchored at the top.
    let verticalCoverage: CGFloat

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
        // Compress only Y, anchored at the top, so the lights cover the top part.
        let inverseHeight = 1 / max(Float(size.height), 1) / Float(verticalCoverage)

        // Uniform work happens once per frame rather than once per fragment.
        return function(
            .float2(1 / max(Float(size.width), 1), inverseHeight),
            .float4(-0.015, 0.13, -0.05, -0.03),
            .float(-1.8 / (spread * spread)),
            .float(1.5 + bloom * 0.12),
            .float3(0, 0, 0),
            .float3(colors[0].x, colors[0].y, colors[0].z),
            .float3(colors[1].x, colors[1].y, colors[1].z),
            .float3(colors[2].x, colors[2].y, colors[2].z),
            .float3(colors[3].x, colors[3].y, colors[3].z),
            .float3(background.x, background.y, background.z)
        )
    }
}
