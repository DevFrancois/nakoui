#include <metal_stdlib>
using namespace metal;

// Swift twin: TabBarOpticsRenderer.Uniforms. Ten SIMD4<Float> values, 160 bytes.
struct TabBarOpticsUniforms {
    float4 geometry; // capsule width/height (points), drawable pixels/point, dark appearance
    float4 capture;  // capsule origin in current UI crop, crop width/height (points)
    float4 material; // light angle (radians), sharp highlight, sampling reach, reduce transparency
    float4 visibleRect; // current UI crop visible minX/minY/maxX/maxY (points)
    float4 previousCapture; // previous UI crop x/y/width/height in window points
    float4 sceneRect; // owned Carousel crop x/y/width/height in window points
    float4 feed; // current UI crop window x/y, UI interpolation, has Carousel
    float4 reflection; // strength, band width (points), saturation, softness
    float4 surface; // uniform opacity, face wash, face+edges mode, edge darkening
    float4 lighting; // soft glow, sharp width, soft width (points), warm/cool balance
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

static float3 tabBarLinearToSRGB(float3 value) {
    value = max(value, float3(0));
    return select(value * 12.92, 1.055 * powr(value, float3(1.0 / 2.4)) - 0.055,
                  value > 0.0031308);
}

static float3 tabBarSRGBToLinear(float3 value) {
    value = max(value, float3(0));
    return select(value / 12.92, powr((value + 0.055) / 1.055, float3(2.4)),
                  value > 0.04045);
}

// Decode each newly captured BGRA8Unorm UI texel once. Subsequent bilinear
// samples and rim filtering operate on cached linear-premultiplied RGBA16Float
// rather than repeating nonlinear color conversion for every reflection tap.
static float4 tabBarDecodeUICapture(float4 value) {
    if (value.a <= 0) return 0;
    return float4(tabBarSRGBToLinear(saturate(value.rgb / value.a)) * value.a, value.a);
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
static void tabBarLaminateRim(float distance, float pixel, float2 rim,
                             float nov, constant TabBarOpticsUniforms &u,
                             thread float3 &light, thread float3 &through) {
    float inward = max(-distance, 0.0);
    float sharpWidth = max(0.55 * pixel, u.lighting.y);
    float softWidth = max(1.1 * pixel, u.lighting.z);
    float sharp = 1 - smoothstep(0.0, sharpWidth, inward);
    float soft = 1 - smoothstep(0.0, softWidth, inward);
    float c = cos(u.material.x), s = sin(u.material.x);
    float2 key = float2(-0.6 * c + 0.8 * s, -0.6 * s - 0.8 * c);
    float facing = dot(rim, key);
    float keyLobe = powr(saturate(facing), 1.6);
    float fillLobe = powr(saturate(-facing), 2.0);
    float fresnel = 0.04 + 0.96 * powr(1 - saturate(nov), 5.0);
    float sharpEnergy = clamp(u.material.y, 0.0, 3.0);
    float softEnergy = clamp(u.lighting.x, 0.0, 3.0);
    float warmth = clamp(u.lighting.w, -1.0, 1.0);
    float3 glint = float3(1.0, 0.965, 0.91) * keyLobe * (1 + warmth)
        * (0.085 * sharp * sharpEnergy + 0.036 * soft * softEnergy);
    glint += float3(0.80, 0.90, 1.0) * fillLobe * (1 - warmth)
        * (0.025 * sharp * sharpEnergy + 0.018 * soft * softEnergy);
    float darkening = clamp(u.surface.w, 0.0, 2.0);
    float shade = (0.018 + 0.026 * fillLobe) * soft * darkening;
    light = light * (1 - shade) + glint * (0.65 + 0.35 * fresnel);
    through *= float3(1 - shade) - float3(0.010, 0.003, 0.001) * soft * fillLobe * darkening;
}

struct TabBarFeedSample {
    float4 color; // linear premultiplied color, including geometric coverage
    float coverage; // geometric eligibility, independent of content alpha
};

// Both UI captures and the owned Carousel crop use premultiplied alpha. Never
// clamp a sample from outside a source onto its border: that would smear colors
// into unrelated regions and leak clipped/offscreen content into the optics.
static TabBarFeedSample tabBarSampleTexture(float2 point, float2 size, float4 visible,
                                            texture2d<float> texture, bool isUI,
                                            float2 capsuleOrigin, float2 capsuleSize) {
    if (any(size <= 0)) return { float4(0), 0 };
    float2 texel = size / float2(texture.get_width(), texture.get_height());
    float2 visibleMin = (ceil(max(visible.xy, float2(0)) / texel) + 0.5) * texel;
    float2 visibleMax = (floor(min(visible.zw, size) / texel) - 0.5) * texel;
    if (any(point < visibleMin) || any(point > visibleMax)) return { float4(0), 0 };
    // Geometric boundaries fade over two texels. Missing rays must not dilute
    // the other side's color, but a tiny arriving footprint must not pop in.
    float2 inside = min((point - visibleMin) / texel, (visibleMax - point) / texel);
    float eligible = smoothstep(0.0, 2.0, min(inside.x, inside.y));
    if (isUI) {
        // UI crops clear this rectangle. Reject the complete bilinear footprint
        // before sampling, so controls and previous optical frames cannot feed
        // back. A direct Carousel scene has no such exclusion.
        float2 excludedMin = capsuleOrigin - 6.0 - texel * 0.5;
        float2 excludedMax = capsuleOrigin + capsuleSize + 6.0 + texel * 0.5;
        float2 outside = max((excludedMin - point) / texel, (point - excludedMax) / texel);
        eligible *= smoothstep(0.0, 2.0, max(outside.x, outside.y));
    }
    if (eligible <= 0) return { float4(0), 0 };
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    return { texture.sample(sampling, point / size, level(0)) * eligible, eligible };
}

static TabBarFeedSample tabBarSampleFeeds(float2 point, constant TabBarOpticsUniforms &u,
                                          texture2d<float> previousUI, texture2d<float> currentUI,
                                          texture2d<float> scene) {
    float2 windowPoint = u.feed.xy + point;
    float interpolation = saturate(u.feed.z);
    TabBarFeedSample ui = tabBarSampleTexture(point, u.capture.zw, u.visibleRect,
                                             currentUI, true, u.capture.xy, u.geometry.xy);
    // Once the blend has finished, avoid a second UI texture read for every
    // blur tap. The window-coordinate mapping also handles moving crop bounds.
    if (interpolation < 1) {
        TabBarFeedSample previous = tabBarSampleTexture(windowPoint - u.previousCapture.xy,
            u.previousCapture.zw, float4(0, 0, u.previousCapture.zw), previousUI, true,
            u.feed.xy + u.capture.xy - u.previousCapture.xy, u.geometry.xy);
        ui.color = mix(previous.color, ui.color, interpolation);
        ui.coverage = mix(previous.coverage, ui.coverage, interpolation);
    }
    if (u.feed.w > 0.5) {
        TabBarFeedSample live = tabBarSampleTexture(windowPoint - u.sceneRect.xy, u.sceneRect.zw,
            float4(0, 0, u.sceneRect.zw), scene, false, float2(0), float2(0));
        ui.color = live.color + ui.color * (1 - live.color.a);
        ui.coverage = live.coverage + ui.coverage * (1 - live.coverage);
    }
    return ui;
}

struct TabBarColorSamples {
    float3 color;
    float alphaWeight;
    float eligibleWeight;
    float requestedWeight;
    float footprint;
};

static float3 tabBarSaturateColor(float3 color, float saturation) {
    float gray = dot(color, float3(0.2126, 0.7152, 0.0722));
    return saturate(mix(float3(gray), color, clamp(saturation, 0.0, 2.0)));
}

static float4 tabBarResolveColor(thread const TabBarColorSamples &samples) {
    if (samples.alphaWeight <= 1e-6 || samples.eligibleWeight <= 1e-6) return 0;
    float meanAlpha = saturate(samples.alphaWeight / samples.eligibleWeight);
    // Normalizing by eligible weight otherwise cancels a first sample's own
    // geometric fade. Retain its footprint explicitly, so a newly reachable
    // source fades in while a fully covered inward neighbor stays strong.
    float confidence = samples.footprint * smoothstep(0.0, 0.04,
        samples.eligibleWeight / max(samples.requestedWeight, 1e-6));
    return float4(samples.color / samples.alphaWeight, meanAlpha * confidence);
}

static void tabBarAccumulateSample(float2 point, float weight,
                                   constant TabBarOpticsUniforms &u,
                                   texture2d<float> previousUI, texture2d<float> currentUI,
                                   texture2d<float> scene,
                                   thread TabBarColorSamples &samples) {
    TabBarFeedSample seen = tabBarSampleFeeds(point, u, previousUI, currentUI, scene);
    samples.color += seen.color.rgb * weight;
    samples.alphaWeight += weight * seen.color.a;
    samples.eligibleWeight += weight * seen.coverage;
    samples.requestedWeight += weight;
    samples.footprint = max(samples.footprint, seen.coverage);
}

static void tabBarSampleSide(float2 origin, float2 direction, float weight, float blur,
                            constant TabBarOpticsUniforms &u, texture2d<float> previousUI,
                            texture2d<float> currentUI, texture2d<float> scene,
                            thread TabBarColorSamples &samples) {
    float2 tangent = float2(-direction.y, direction.x);
    // Finite Gaussian-like footprint. Every individual tap is checked before
    // sampling, including taps that straddle a crop's visible boundary.
    tabBarAccumulateSample(origin, weight * 0.28, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin + tangent * blur, weight * 0.12, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin - tangent * blur, weight * 0.12, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin + direction * blur, weight * 0.12, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin - direction * blur, weight * 0.12, u, previousUI, currentUI, scene, samples);
    float2 diagonal = (tangent + direction) * (blur * 0.7);
    float2 otherDiagonal = (tangent - direction) * (blur * 0.7);
    tabBarAccumulateSample(origin + diagonal, weight * 0.06, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin - diagonal, weight * 0.06, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin + otherDiagonal, weight * 0.06, u, previousUI, currentUI, scene, samples);
    tabBarAccumulateSample(origin - otherDiagonal, weight * 0.06, u, previousUI, currentUI, scene, samples);
}

static float4 tabBarNearbyColor(float2 point, float inward, float2 normal, float bandDepth,
                               constant TabBarOpticsUniforms &u, texture2d<float> previousUI,
                               texture2d<float> currentUI, texture2d<float> scene) {
    float t = saturate(inward / bandDepth);
    if (t >= 1 || u.material.z <= 0 || u.reflection.x <= 0) return 0;

    // Carousel's circular lens profile reaches furthest out at the contour, and
    // settles inward. The UI crop excludes the bar to avoid feedback; direct
    // Carousel pixels underneath the receiver remain valid sources.
    float circular = 1 - sqrt(t * (2 - t));
    float reach = max(u.material.z, 8.0);
    float outside = 8.0 + reach * 0.55 * circular;
    float blur = min(reach * 0.23, mix(10.0, 22.0, smoothstep(0.0, 0.65, t))) * u.reflection.w;
    float2 size = u.geometry.xy;
    float2 sourcePoint = u.capture.xy + point;
    float2 directions[] = { float2(-1, 0), float2(1, 0), float2(0, -1), float2(0, 1) };
    float distances[] = { point.x, size.x - point.x, point.y, size.y - point.y };
    TabBarColorSamples samples = { float3(0), 0, 0, 0, 0 };

    tabBarSampleSide(sourcePoint + normal * (reach * 0.55 * circular), normal,
                     1.0, blur, u, previousUI, currentUI, scene, samples);

    for (uint side = 0; side < 4; ++side) {
        float2 direction = directions[side];
        float distance = max(distances[side], 0.0);
        float facing = saturate(dot(normal, direction));
        float proximity = 1.0 / (1.0 + (distance / reach) * (distance / reach));
        // The small opposing contribution matters at screen edges: if outward
        // rays leave the window's visible frame, the inward side remains a source.
        // Side anchors preserve the fragment's along-bar coordinate, so colors
        // change along the capsule rather than becoming a single averaged tint.
        float weight = (0.12 + 0.88 * facing * facing) * proximity;
        float2 origin = sourcePoint + direction * (distance + outside);
        tabBarSampleSide(origin, direction, weight, blur, u, previousUI, currentUI, scene, samples);
    }

    float band = 1 - t;
    float4 nearby = tabBarResolveColor(samples);
    return float4(tabBarSaturateColor(nearby.rgb, u.reflection.z),
                  saturate(0.62 * u.reflection.x * band * band * nearby.a));
}

// A tiny longitudinal color field keeps the broad face soft without executing
// the 45-tap rim filter for every body pixel. Nine feed samples per texel, 64
// texels total, on the same command buffer as the optical pass. The center line
// picks up direct Carousel pixels; UI contributes only from the exterior lines.
fragment float4 tabBarWashFragment(TabBarOpticsVertexOutput in [[stage_in]],
                                   constant TabBarOpticsUniforms &u [[buffer(0)]],
                                   texture2d<float> previousUI [[texture(0)]],
                                   texture2d<float> currentUI [[texture(1)]],
                                   texture2d<float> scene [[texture(2)]]) {
    float2 size = max(u.geometry.xy, float2(1));
    bool vertical = size.y > size.x;
    float2 along = vertical ? float2(0, 1) : float2(1, 0);
    float2 across = vertical ? float2(1, 0) : float2(0, 1);
    float length = vertical ? size.y : size.x;
    float width = vertical ? size.x : size.y;
    float outside = 8.0 + 0.30 * u.material.z;
    float spread = 0.25 * u.material.z * u.reflection.w;
    float2 center = u.capture.xy + along * (in.uv.x * length) + across * (width * 0.5);
    const float offsets[] = { -1.0, 0.0, 1.0 };
    const float weights[] = { 0.25, 0.5, 0.25 };
    TabBarColorSamples samples = { float3(0), 0, 0, 0, 0 };
    for (uint line = 0; line < 3; ++line) {
        float lineWeight = line == 1 ? 0.5 : 1.0;
        float2 origin = center + across * (offsets[line] * (width * 0.5 + outside));
        for (uint tap = 0; tap < 3; ++tap) {
            tabBarAccumulateSample(origin + along * (offsets[tap] * spread),
                lineWeight * weights[tap], u, previousUI, currentUI, scene, samples);
        }
    }
    float4 nearby = tabBarResolveColor(samples);
    float3 neutral = float3(mix(0.90, 0.018, saturate(u.geometry.w)));
    float3 color = tabBarSaturateColor(nearby.rgb, u.reflection.z);
    // Perceptual blending bounds the wash's visible contrast in Dark Mode.
    // Store the complete linear material tint: the main pass needs one read,
    // with no extra per-fragment nonlinear conversion or source filtering.
    float amount = saturate(u.surface.y * nearby.a);
    float3 tinted = tabBarSRGBToLinear(mix(tabBarLinearToSRGB(neutral),
                                         tabBarLinearToSRGB(color), amount));
    return float4(tinted, 1);
}

fragment float4 tabBarOpticsFragment(TabBarOpticsVertexOutput in [[stage_in]],
                                    constant TabBarOpticsUniforms &u [[buffer(0)]],
                                    texture2d<float> previousUI [[texture(0)]],
                                    texture2d<float> currentUI [[texture(1)]],
                                    texture2d<float> scene [[texture(2)]],
                                    texture2d<float> wash [[texture(3)]]) {
    float2 size = max(u.geometry.xy, float2(1));
    float2 point = in.uv * size;
    float2 normal;
    float distance = tabBarCapsuleDistance(point, size, normal);
    float pixel = 1.0 / max(u.geometry.z, 1.0);
    float coverage = 1 - smoothstep(-0.5 * pixel, 0.5 * pixel, distance);
    if (coverage <= 0) return 0;

    bool opaque = u.material.w > 0.5;
    float dark = saturate(u.geometry.w);
    float inward = max(-distance, 0.0);
    float bandDepth = min(u.reflection.y, min(size.x, size.y) * 0.32);
    // One mostly solid material, with the same slight transparency across the
    // entire capsule. Color reflections tint that material, not a clear border
    // around an unrelated opaque center.
    float baseAlpha = opaque ? 1.0 : saturate(u.surface.x);
    float3 neutral = float3(mix(0.90, 0.018, dark));
    float3 color = neutral;
    if (!opaque) {
        if (u.surface.z > 0.5 && u.surface.y > 0) {
            constexpr sampler filtering(coord::normalized, address::clamp_to_edge, filter::linear);
            float coordinate = size.y > size.x ? in.uv.y : in.uv.x;
            color = wash.sample(filtering, float2(coordinate, 0.5), level(0)).rgb;
        }
        float4 nearby = tabBarNearbyColor(point, inward, normal, max(bandDepth, 1.0), u, previousUI, currentUI, scene);
        color = mix(color, nearby.rgb, nearby.a);
    }

    float3 light = color * baseAlpha;
    float3 through = float3(1 - baseAlpha);

    float curve = saturate(inward / max(bandDepth, 1.0));
    float nov = sqrt(curve * (2 - curve));
    tabBarLaminateRim(distance, pixel, normal, nov, u, light, through);
    // Standard premultiplied source-over: approximate the rim's slightly colored
    // attenuation with scalar transmission, without dual-source blending.
    float attenuation = 1 - dot(through, float3(1.0 / 3.0));
    // A glint adds light even on a transparent base. Give it enough coverage
    // for valid premultiplied output without clipping it to the darkening lobe.
    float alpha = saturate(max(attenuation, max(light.r, max(light.g, light.b))));
    float4 linearPremultiplied = float4(clamp(light, float3(0), float3(alpha)), alpha) * coverage;
    // CAMetalLayer/Core Animation composites encoded premultiplied sRGB bytes.
    // A plain linear-premultiplied write to an _srgb target would encode RGB
    // after premultiplication: e.g. 0.27 RGB / 0.30 alpha becomes 0.556 / 0.30,
    // blowing the translucent surface out to white. Encode straight color,
    // multiply in encoded space, then undo the target's automatic encoding.
    float3 encodedPremultiplied = tabBarLinearToSRGB(
        linearPremultiplied.rgb / max(linearPremultiplied.a, 1e-6)) * linearPremultiplied.a;
    return float4(tabBarSRGBToLinear(encodedPremultiplied), linearPremultiplied.a);
}

// Copy only the visible, nearby part of Carousel into a consumer-owned texture
// while the producer command buffer still owns its frame. This stays entirely
// on the GPU and preserves premultiplied alpha for source-over composition.
fragment float4 tabBarSceneCopyFragment(TabBarOpticsVertexOutput in [[stage_in]],
                                        constant float4 &sourceRect [[buffer(0)]],
                                        texture2d<float> scene [[texture(0)]]) {
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(scene.get_width(), scene.get_height());
    float2 firstCenter = (ceil(max(sourceRect.xy, float2(0)) * size) + 0.5) / size;
    float2 lastCenter = (floor(min(sourceRect.xy + sourceRect.zw, float2(1)) * size) - 0.5) / size;
    if (any(firstCenter > lastCenter)) return 0;
    float2 uv = clamp(sourceRect.xy + in.uv * sourceRect.zw, firstCenter, lastCenter);
    return scene.sample(sampling, uv, level(0));
}

// A small preparation pass runs only when a new CPU UI capture arrives. The
// output has the same dimensions and linear premultiplication as GPU scenes.
fragment float4 tabBarPrepareUIFragment(TabBarOpticsVertexOutput in [[stage_in]],
                                        texture2d<float> capture [[texture(0)]]) {
    uint2 pixel = min(uint2(in.position.xy), uint2(capture.get_width(), capture.get_height()) - 1);
    return tabBarDecodeUICapture(capture.read(pixel));
}
