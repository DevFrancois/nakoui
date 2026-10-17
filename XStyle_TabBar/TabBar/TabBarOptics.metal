#include <metal_stdlib>
using namespace metal;

// Swift twin: TabBarOpticsUniforms. Three SIMD4<Float> values, 48 bytes.
struct TabBarOpticsUniforms {
    float4 geometry; // capsule width/height (points), drawable pixels/point, dark appearance
    float4 capture;  // capsule origin in captured crop (points), crop width/height (points)
    float4 material; // light angle (radians), highlight, sampling reach (points), reduce transparency
};

struct TabBarOpticsVertexOutput {
    float4 position [[position]];
    float2 uv;
};

vertex TabBarOpticsVertexOutput tabBarOpticsVertex(uint vertexID [[vertex_id]]) {
    // One oversized triangle. UVs follow UIKit's top-left coordinate system.
    const float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    float2 p = positions[vertexID];
    return { float4(p, 0, 1), float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5) };
}

static float tabBarCapsuleDistance(float2 p, float2 size, thread float2 &normal) {
    float2 halfSize = size * 0.5;
    float radius = min(halfSize.x, halfSize.y);
    float2 centered = p - halfSize;
    float2 segmentHalf = max(halfSize - radius, float2(0));
    float2 delta = centered - clamp(centered, -segmentHalf, segmentHalf);
    float magnitude = length(delta);
    normal = magnitude > 1e-5 ? delta / magnitude : float2(0, -1);
    return magnitude - radius;
}

// Adapted from Carousel's carouselLaminateRim. Keep its independent sharp/soft
// profiles, warm key, cooler opposing lobe, Fresnel response and contact darkening.
// The capsule's circular cross-section supplies the view/normal term that the 3D
// slab renderer normally obtains from its geometry.
static void tabBarLaminateRim(float distance, float bevel, float pixel, float2 rim,
                             float nov, constant TabBarOpticsUniforms &u,
                             thread float3 &light, thread float3 &through) {
    float inward = max(-distance, 0.0);
    float sharpWidth = max(0.55 * pixel, 0.38);
    float softWidth = max(1.1 * pixel, min(bevel * 1.65, 3.5));
    float sharp = 1 - smoothstep(0.0, sharpWidth, inward);
    float soft = 1 - smoothstep(0.0, softWidth, inward);
    float c = cos(u.material.x), s = sin(u.material.x);
    float2 key = float2(-0.6 * c + 0.8 * s, -0.6 * s - 0.8 * c);
    float facing = dot(rim, key);
    float keyLobe = powr(saturate(facing), 1.6);
    float fillLobe = powr(saturate(-facing), 2.0);
    float fresnel = 0.04 + 0.96 * powr(1 - saturate(nov), 5.0);
    float energy = min(max(u.material.y, 0.0), 1.5);
    float3 glint = float3(1.0, 0.965, 0.91) * keyLobe * (0.085 * sharp + 0.036 * soft);
    glint += float3(0.80, 0.90, 1.0) * fillLobe * (0.025 * sharp + 0.018 * soft);
    float shade = (0.018 + 0.026 * fillLobe) * soft;
    light = light * (1 - shade) + glint * (0.65 + 0.35 * fresnel) * energy;
    through *= float3(1 - shade) - float3(0.010, 0.003, 0.001) * soft * fillLobe;
}

static void tabBarAccumulateSample(float2 point, float weight,
                                   constant TabBarOpticsUniforms &u,
                                   texture2d<float> backdrop,
                                   thread float3 &color, thread float &total) {
    float2 cropSize = max(u.capture.zw, float2(1));
    float2 halfTexel = cropSize / float2(backdrop.get_width(), backdrop.get_height()) * 0.5;
    if (any(point < halfTexel) || any(point > cropSize - halfTexel)) return;

    // The window capture includes this view. Reject its entire bounding rectangle,
    // not just its curved silhouette, plus a six-point gutter AND the bilinear
    // footprint. No icon, selection highlight or prior optical frame can feed back.
    float2 excludedMin = u.capture.xy - 6.0 - halfTexel;
    float2 excludedMax = u.capture.xy + u.geometry.xy + 6.0 + halfTexel;
    if (all(point >= excludedMin) && all(point <= excludedMax)) return;

    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 seen = backdrop.sample(sampling, point / cropSize, level(0));
    float sampleWeight = weight * seen.a;
    color += seen.rgb / max(seen.a, 1e-4) * sampleWeight;
    total += sampleWeight;
}

static void tabBarSampleSide(float2 origin, float2 direction, float weight, float blur,
                            constant TabBarOpticsUniforms &u, texture2d<float> backdrop,
                            thread float3 &color, thread float &total) {
    float2 tangent = float2(-direction.y, direction.x);
    // Finite Gaussian-like footprint. Every individual tap is checked before
    // sampling, including taps that straddle the screen boundary or exclusion.
    tabBarAccumulateSample(origin, weight * 0.28, u, backdrop, color, total);
    tabBarAccumulateSample(origin + tangent * blur, weight * 0.12, u, backdrop, color, total);
    tabBarAccumulateSample(origin - tangent * blur, weight * 0.12, u, backdrop, color, total);
    tabBarAccumulateSample(origin + direction * blur, weight * 0.12, u, backdrop, color, total);
    tabBarAccumulateSample(origin - direction * blur, weight * 0.12, u, backdrop, color, total);
    float2 diagonal = (tangent + direction) * (blur * 0.7);
    float2 otherDiagonal = (tangent - direction) * (blur * 0.7);
    tabBarAccumulateSample(origin + diagonal, weight * 0.06, u, backdrop, color, total);
    tabBarAccumulateSample(origin - diagonal, weight * 0.06, u, backdrop, color, total);
    tabBarAccumulateSample(origin + otherDiagonal, weight * 0.06, u, backdrop, color, total);
    tabBarAccumulateSample(origin - otherDiagonal, weight * 0.06, u, backdrop, color, total);
}

static float4 tabBarNearbyColor(float2 point, float inward, float2 normal, float bandDepth,
                               constant TabBarOpticsUniforms &u, texture2d<float> backdrop) {
    float t = saturate(inward / bandDepth);
    if (t >= 1 || u.material.z <= 0) return 0;

    // Carousel's circular lens profile reaches furthest out at the contour, and
    // settles inward. Here rays stop outside the receiver to avoid sampling the
    // tab bar captured in the window. The color always comes from real pixels.
    float circular = 1 - sqrt(t * (2 - t));
    float reach = max(u.material.z, 8.0);
    float outside = 8.0 + reach * 0.55 * circular;
    float blur = min(reach * 0.23, mix(10.0, 22.0, smoothstep(0.0, 0.65, t)));
    float2 size = u.geometry.xy;
    float2 cropPoint = u.capture.xy + point;
    float2 directions[] = { float2(-1, 0), float2(1, 0), float2(0, -1), float2(0, 1) };
    float distances[] = { point.x, size.x - point.x, point.y, size.y - point.y };
    float3 color = 0;
    float total = 0;

    for (uint side = 0; side < 4; ++side) {
        float2 direction = directions[side];
        float distance = max(distances[side], 0.0);
        float facing = saturate(dot(normal, direction));
        float proximity = 1.0 / (1.0 + (distance / reach) * (distance / reach));
        // The small opposing contribution matters at screen edges: if outward
        // rays leave the captured window, the inward side remains a real source.
        // Side anchors preserve the fragment's along-bar coordinate, so colors
        // change along the capsule rather than becoming a single averaged tint.
        float weight = (0.12 + 0.88 * facing * facing) * proximity;
        float2 origin = cropPoint + direction * (distance + outside);
        tabBarSampleSide(origin, direction, weight, blur, u, backdrop, color, total);
    }

    if (total <= 1e-4) return 0;
    float band = 1 - t;
    return float4(color / total, 0.62 * band * band);
}

fragment float4 tabBarOpticsFragment(TabBarOpticsVertexOutput in [[stage_in]],
                                    constant TabBarOpticsUniforms &u [[buffer(0)]],
                                    texture2d<float> backdrop [[texture(0)]]) {
    float2 size = max(u.geometry.xy, float2(1));
    float2 point = in.uv * size;
    float2 normal;
    float distance = tabBarCapsuleDistance(point, size, normal);
    float pixel = 1.0 / max(u.geometry.z, 1.0);
    float coverage = 1 - smoothstep(-0.5 * pixel, 0.5 * pixel, distance);
    if (coverage <= 0) return 0;

    bool opaque = u.material.w > 0.5;
    float dark = saturate(u.geometry.w);
    float baseAlpha = opaque ? 1.0 : mix(0.44, 0.38, dark);
    float3 neutral = float3(mix(0.90, 0.018, dark));
    float3 light = neutral * baseAlpha;
    float3 through = float3(1 - baseAlpha);

    float bandDepth = min(11.0, min(size.x, size.y) * 0.32);
    float inward = max(-distance, 0.0);
    if (!opaque) {
        float4 nearby = tabBarNearbyColor(point, inward, normal, max(bandDepth, 1.0), u, backdrop);
        light = mix(light, nearby.rgb, nearby.a);
        through *= 1 - nearby.a;
    }

    float curve = saturate(inward / max(bandDepth, 1.0));
    float nov = sqrt(curve * (2 - curve));
    tabBarLaminateRim(distance, 2.1, pixel, normal, nov, u, light, through);
    // Standard premultiplied source-over: approximate the rim's slightly colored
    // attenuation with scalar transmission, without dual-source blending.
    float alpha = saturate(1 - dot(through, float3(1.0 / 3.0)));
    return float4(clamp(light, float3(0), float3(alpha)), alpha) * coverage;
}
