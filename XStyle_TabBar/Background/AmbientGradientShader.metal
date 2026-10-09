//
//  AmbientGradientShader.metal
//  Ported from ZoomInUIKit's GridAmbientShader.metal.
//

#include <metal_stdlib>
using namespace metal;

inline float2 ambientGradientPoint(float2 position, float2 inverseSize, float3 warp) {
    float2 point = position * inverseSize;

    // Uniform branch: palette-only changes and resting frames need no sine work.
    if (warp.x > 0.0) {
        point.x += sin(point.y * 4.2 + point.x * 1.6) * warp.x;
        point.y += sin(point.x * 5.0 + warp.z) * warp.y;
    }

    return point;
}

// Float fallback preserves the range of custom, extended-RGB palettes.
[[ stitchable ]] half4 ambientLighting(
    float2 position,
    float2 inverseSize,
    float4 centerY,
    float falloffScale,
    float coverageScale,
    float3 warp,
    float3 color0,
    float3 color1,
    float3 color2,
    float3 color3,
    float3 background
) {
    float2 point = ambientGradientPoint(position, inverseSize, warp);

    // Four Gaussian sources, with frame-wide divisions/interpolation done in Swift.
    // Constant squared reciprocal radii are folded by the Metal compiler.
    const float4 inverseRadiusXSquared = 1.0 / (float4(0.42, 0.36, 0.50, 0.39)
        * float4(0.42, 0.36, 0.50, 0.39));
    const float4 inverseRadiusYSquared = 1.0 / (float4(0.25, 0.22, 0.32, 0.27)
        * float4(0.25, 0.22, 0.32, 0.27));
    float4 dx = point.x - float4(0.02, 0.25, 0.57, 1.03);
    float4 dy = point.y - centerY;
    float4 distanceSquared = dx * dx * inverseRadiusXSquared
        + dy * dy * inverseRadiusYSquared;
    float4 weights = exp(distanceSquared * falloffScale) * float4(1.25, 1.05, 1.40, 1.15);
    float total = weights.x + weights.y + weights.z + weights.w;

    // Keep float precision through the soft tails to avoid introducing banding.
    float3 weightedColors = (
        color0 * weights.x + color1 * weights.y + color2 * weights.z + color3 * weights.w
    );
    float coverage = 1.0 - exp(-total * coverageScale);
    float3 result = background * (1.0 - coverage)
        + weightedColors * (coverage / max(total, 0.00001));

    // Direct opaque shape fill; SwiftUI applies shape coverage without a source texture.
    return half4(half3(result), 1.0h);
}

// Swift selects this entry point only when every palette component is in [0, 1].
[[ stitchable ]] half4 ambientLightingFast(
    float2 position,
    float2 inverseSize,
    float4 centerY,
    float falloffScale,
    float coverageScale,
    float3 warp,
    float3 color0,
    float3 color1,
    float3 color2,
    float3 color3,
    float3 background
) {
    float2 point = ambientGradientPoint(position, inverseSize, warp);

    const float4 inverseRadiusXSquared = 1.0 / (float4(0.42, 0.36, 0.50, 0.39)
        * float4(0.42, 0.36, 0.50, 0.39));
    const float4 inverseRadiusYSquared = 1.0 / (float4(0.25, 0.22, 0.32, 0.27)
        * float4(0.25, 0.22, 0.32, 0.27));

    // Subtract in float before converting to half to retain accurate source centers.
    half4 dx = half4(point.x - float4(0.02, 0.25, 0.57, 1.03));
    half4 dy = half4(point.y - centerY);
    half4 distanceSquared = dx * dx * half4(inverseRadiusXSquared)
        + dy * dy * half4(inverseRadiusYSquared);
    half4 weights = exp2(distanceSquared * half(falloffScale * 1.4426950408889634))
        * half4(1.25h, 1.05h, 1.40h, 1.15h);
    float total = float(weights.x) + float(weights.y) + float(weights.z) + float(weights.w);

    // Small color deltas limit half-precision error; coverage and blending stay float.
    half3 weightedDelta = (
        half3(color0 - background) * weights.x
        + half3(color1 - background) * weights.y
        + half3(color2 - background) * weights.z
        + half3(color3 - background) * weights.w
    );
    float coverage = 1.0 - exp2(-total * (coverageScale * 1.4426950408889634));
    float3 result = background + float3(weightedDelta) * (coverage / max(total, 0.00001));

    return half4(half3(result), 1.0h);
}
