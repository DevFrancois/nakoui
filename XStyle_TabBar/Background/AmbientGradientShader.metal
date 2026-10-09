//
//  AmbientGradientShader.metal
//  Ported from ZoomInUIKit's GridAmbientShader.metal.
//

#include <metal_stdlib>
using namespace metal;

// Weights of the four Gaussian lights along one edge, at a point measured
// from that edge.
inline float4 ambientEdgeWeights(float x, float y, float4 centerY, float falloffScale) {
    const float4 inverseRadiusXSquared = 1.0 / (float4(0.42, 0.36, 0.50, 0.39)
        * float4(0.42, 0.36, 0.50, 0.39));
    const float4 inverseRadiusYSquared = 1.0 / (float4(0.25, 0.22, 0.32, 0.27)
        * float4(0.25, 0.22, 0.32, 0.27));
    float4 dx = x - float4(0.02, 0.25, 0.57, 1.03);
    float4 dy = y - centerY;
    float4 distanceSquared = dx * dx * inverseRadiusXSquared
        + dy * dy * inverseRadiusYSquared;
    return exp(distanceSquared * falloffScale) * float4(1.25, 1.05, 1.40, 1.15);
}

// Four lights along the top and four mirrored along the bottom, all fading
// into one background. Float throughout: there are two sets of soft tails, and
// the surface is drawn once rather than every frame of a swipe.
[[ stitchable ]] half4 ambientLightingEdges(
    float2 position,
    float2 inverseSize,
    float bottomInverseHeight,
    float height,
    float4 centerY,
    float falloffScale,
    float coverageScale,
    float3 top0,
    float3 top1,
    float3 top2,
    float3 top3,
    float3 bottom0,
    float3 bottom1,
    float3 bottom2,
    float3 bottom3,
    float3 background
) {
    float x = position.x * inverseSize.x;
    float4 topWeights = ambientEdgeWeights(x, position.y * inverseSize.y, centerY, falloffScale);
    float4 bottomWeights = ambientEdgeWeights(
        x, (height - position.y) * bottomInverseHeight, centerY, falloffScale
    );
    float total = dot(topWeights, float4(1.0)) + dot(bottomWeights, float4(1.0));

    float3 weightedColors = (
        top0 * topWeights.x + top1 * topWeights.y + top2 * topWeights.z + top3 * topWeights.w
        + bottom0 * bottomWeights.x + bottom1 * bottomWeights.y
        + bottom2 * bottomWeights.z + bottom3 * bottomWeights.w
    );
    float coverage = 1.0 - exp(-total * coverageScale);
    float3 result = background * (1.0 - coverage)
        + weightedColors * (coverage / max(total, 0.00001));

    return half4(half3(result), 1.0h);
}
