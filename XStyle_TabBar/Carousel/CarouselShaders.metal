#include <metal_stdlib>
using namespace metal;

struct CarouselVertex {
    float4 position [[position]];
    float2 uv;
};

// The CPU resolves everything that is constant across a card, so fragments only
// evaluate what varies per pixel.
struct CarouselCardUniforms {
    float2 viewport;
    float2 center;
    float2 rotation;
    float2 quadCenter;
    float2 quadHalf;
    float2 imageHalf;
    float2 frameHalf;
    float2 uvScale;
    float2 shadowOffset;
    float imageRadius;
    float frameRadius;
    float edgeWidth;
    float opacity;
    float tint;
    float shadowAlpha;
    float shadowFalloff;
    float occlusion;
    uint occluderCount;
    /// Turn about the card's vertical axis, radians (0 for a flat card).
    float turn;
    /// Press tilt after the turn: bottom edge away (x), right edge away (y), radians.
    float tiltX;
    float tiltY;
};

struct CarouselOccluderUniforms {
    float2 center;
    float2 cardSize;
    float2 rotation;
    float opacity;
    float cornerRadius;
};

// Card pipelines compile only the parts a draw needs. Plain wheel cards, the
// default, skip the Metal frame, the shadow and the occlusion fade entirely.
// Promoted cards add the shadow and occlusion; shadow-only draws, under native
// glass, are promoted draws without the image.
constant bool carouselFramed [[function_constant(0)]];
constant bool carouselPromoted [[function_constant(1)]];
constant bool carouselShadowOnly [[function_constant(2)]];
constant bool carouselDrawsImage = !carouselShadowOnly;

// Appearance experiments specialise only the slab pipelines. Leaving every switch
// off retains the original equations; plain cards never compile these material paths.
constant bool carouselRefinedReflections [[function_constant(5)]];
constant bool carouselRefractiveEdges [[function_constant(6)]];
constant bool carouselPaperShading [[function_constant(7)]];
constant bool carouselSoftShadows [[function_constant(8)]];
// CarouselCardMaterial's index. Clear retains the original optical path; the
// other variants compile only their own plastic finish and transmission.
constant uint carouselMaterial [[function_constant(9)]];
constant bool carouselFrosted = carouselMaterial == 1;
constant bool carouselSmoked = carouselMaterial == 2;
constant bool carouselPrismatic = carouselMaterial == 3;
constant uint carouselColorStyle [[function_constant(10)]];
constant bool carouselColorsCard = carouselColorStyle != 0;
constant bool carouselForegroundReflections [[function_constant(11)]];
constant bool carouselSceneDepth [[function_constant(12)]];
constant bool carouselSkipHiddenShading [[function_constant(13)]];
constant bool carouselLegacySources = !carouselSceneDepth;
constant bool carouselLegacyOcclusion = carouselPromoted && !carouselSceneDepth;
constant bool carouselRefinedSources = carouselRefractiveEdges && !carouselSceneDepth;
constant bool carouselPicksUpForeground = carouselSceneDepth && carouselRefractiveEdges && carouselForegroundReflections;

struct CarouselCardVertex {
    float4 position [[position]];
    float2 local;
};

float3 carouselPreviewBackground(float y) {
    // Linear-light equivalents of sRGB #C2D6FC (top) and #EEEEF3 (bottom).
    return mix(float3(0.539479489, 0.672443157, 0.973445290),
               float3(0.854992608, 0.854992608, 0.896269353), clamp(y, 0.0, 1.0));
}

vertex CarouselVertex carouselFullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 points[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    CarouselVertex output;
    output.position = float4(points[vertexID], 0, 1);
    output.uv = float2(points[vertexID].x * 0.5 + 0.5, 0.5 - points[vertexID].y * 0.5);
    return output;
}

struct CarouselFeatureViewportUniforms {
    float4 crop;
    uint alphaMode;
    uint padding0;
    uint padding1;
    uint padding2;
};

// Posters already contain linear-premultiplied color. Video output contains encoded
// BGRA, whose alpha association is supplied by Core Video. Normalize once per new
// frame, before the shared mip chain is used by the face and every optical source.
fragment float4 carouselFeatureViewportFragment(CarouselVertex input [[stage_in]],
                                                constant CarouselFeatureViewportUniforms &u [[buffer(0)]],
                                                texture2d<float> source [[texture(0)]],
                                                sampler sampling [[sampler(0)]]) {
    float2 uv = u.crop.xy + input.uv * u.crop.zw;
    if (any(uv < 0) || any(uv > 1)) return float4(0);
    float4 color = source.sample(sampling, uv, level(0));
    if (u.alphaMode == 0) return color;
    float alpha = saturate(color.a);
    float3 encoded = u.alphaMode == 1 ? color.rgb / max(alpha, 1e-6) : color.rgb;
    encoded = saturate(encoded);
    float3 linear = select(pow((encoded + 0.055) / 1.055, 2.4), encoded / 12.92,
                           encoded <= 0.04045);
    return float4(linear * alpha, alpha);
}

// Each card rasterizes a rotated quad around its frame and antialiasing margin or,
// when lifted, around its offset shadow. Card-local coordinates are affine in screen
// space, so the rasterizer interpolates them exactly and no fragment transforms its
// position. A turning card is rotated about its vertical axis and seen in perspective
// from twice its larger outer side, as Core Animation's m34 = -1/d does for its views;
// its clip w makes the rasterizer interpolate the local coordinates perspective-correctly.
vertex CarouselCardVertex carouselCardVertex(uint vertexID [[vertex_id]],
                                             constant CarouselCardUniforms &u [[buffer(0)]]) {
    const float2 corners[] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 local = u.quadCenter + corners[vertexID] * u.quadHalf;
    float2 plane = local;
    float w = 1;
    if (u.turn != 0 || u.tiltX != 0 || u.tiltY != 0) {
        // Ry(tiltY)·Rx(tiltX)·Ry(turn), with z measured away from the viewer.
        float distance = 4 * max(u.frameHalf.x, u.frameHalf.y);
        float3 p = float3(local, 0);
        float ct = cos(u.turn), st = sin(u.turn);
        p = float3(p.x * ct - p.z * st, p.y, p.x * st + p.z * ct);
        float cx = cos(u.tiltX), sx = sin(u.tiltX);
        p = float3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx);
        float cy = cos(u.tiltY), sy = sin(u.tiltY);
        p = float3(p.x * cy - p.z * sy, p.y, p.x * sy + p.z * cy);
        w = 1 + p.z / distance;
        plane = p.xy / w;
    }
    float c = u.rotation.x, s = u.rotation.y;
    float2 uv = (u.center + float2(plane.x * c - plane.y * s, plane.x * s + plane.y * c)) / u.viewport;
    CarouselCardVertex output;
    output.position = float4(float2(uv.x * 2 - 1, 1 - uv.y * 2) * w, 0, w);
    output.local = local;
    return output;
}

// Cards in front of a live view are drawn and blended in linear light like the main
// drawable, into an sRGB texture. Core Animation composites the front layer in encoded
// sRGB, so it receives the straight colour encoded, then premultiplied: translucent glass
// frames keep their brightness instead of turning whitish over the live view.
fragment float4 carouselFrontCompositeFragment(CarouselVertex input [[stage_in]],
                                               texture2d<float> cards [[texture(0)]]) {
    constexpr sampler linearSampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = cards.sample(linearSampling, input.uv, level(0));
    if (color.a <= 0.0) return float4(0);
    float3 straight = clamp(color.rgb / color.a, 0.0, 1.0);
    float3 encoded = select(1.055 * pow(straight, 1.0 / 2.4) - 0.055, straight * 12.92,
                            straight <= 0.0031308);
    return float4(encoded * color.a, color.a);
}

// Both targets are sRGB: sampling decodes to linear premultiplied color and the
// drawable attachment encodes it exactly once. UIKit layers never enter this pass.
fragment float4 carouselSceneCompositeFragment(CarouselVertex input [[stage_in]],
                                               texture2d<float> scene [[texture(0)]]) {
    constexpr sampler linearSampling(coord::normalized, address::clamp_to_edge, filter::linear);
    return scene.sample(linearSampling, input.uv, level(0));
}

fragment float4 carouselBackgroundFragment(CarouselVertex input [[stage_in]],
                                           constant float &scrimOpacity [[buffer(0)]]) {
    return float4(carouselPreviewBackground(input.uv.y) * (1 - scrimOpacity), 1);
}

float roundedDistance(float2 point, float2 halfSize, float radius) {
    float2 q = abs(point) - halfSize + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

float2 carouselRoundedNormal(float2 point, float2 halfSize, float radius) {
    float2 edge = abs(point) - halfSize + radius;
    float2 corner = max(edge, 0.0);
    if (dot(corner, corner) > 0.000001) return normalize(corner) * sign(point);
    return edge.x > edge.y ? float2(sign(point.x), 0) : float2(0, sign(point.y));
}

fragment float4 carouselCardFragment(CarouselCardVertex input [[stage_in]],
                                     constant CarouselCardUniforms &u [[buffer(0)]],
                                     constant CarouselOccluderUniforms *occluders
                                         [[buffer(1), function_constant(carouselPromoted)]],
                                     texture2d<float> image [[texture(0), function_constant(carouselDrawsImage)]],
                                     sampler sampling [[sampler(0), function_constant(carouselDrawsImage)]]) {
    float2 local = input.local;
    float distance = roundedDistance(local, u.imageHalf, u.imageRadius);
    float aa = max(fwidth(distance), 0.35);
    float coverage = 1 - smoothstep(-aa * 0.5, aa * 0.5, distance);
    float4 color = float4(0);
    if (carouselDrawsImage) {
        color = image.sample(sampling, local * u.uvScale + 0.5);
        float edge = 1 - smoothstep(0.0, u.edgeWidth, max(0.0, -distance));
        color.rgb = min(float3(color.a), color.rgb + 0.07 * edge * color.a);
        color *= coverage;
        if (carouselFramed) {
            // The frame is an annulus around the unmodified image. Its material is
            // translucent geometry with a restrained rim; it never samples a backdrop.
            float outerDistance = roundedDistance(local, u.frameHalf, u.frameRadius);
            float outerAA = max(fwidth(outerDistance), 0.35);
            float outerCoverage = 1 - smoothstep(-outerAA * 0.5, outerAA * 0.5, outerDistance);
            float ringCoverage = max(0.0, outerCoverage - coverage);
            // Derivatives remain outside the pixel-varying branch. Image interiors
            // and empty space have no frame contribution and need no rim lighting.
            if (ringCoverage > 0) {
                float2 normal = carouselRoundedNormal(local, u.frameHalf, u.frameRadius);
                float2 screenNormal = float2(normal.x * u.rotation.x - normal.y * u.rotation.y,
                                             normal.x * u.rotation.y + normal.y * u.rotation.x);
                float highlight = pow(clamp(dot(screenNormal, float2(-0.6, -0.8)), 0.0, 1.0), 4.0);
                float depth = clamp(dot(screenNormal, float2(0.6, 0.8)), 0.0, 1.0);
                float outerRim = 1 - smoothstep(outerAA * 0.5, outerAA * 0.5 + 1.1, max(0.0, -outerDistance));
                float innerRim = 1 - smoothstep(aa * 0.5, aa * 0.5 + 0.8, max(0.0, distance));
                float alpha = 0.20 + 0.20 * outerRim + 0.07 * innerRim + 0.14 * highlight * outerRim;
                float3 tint = clamp(float3(0.82, 0.86, 0.91) + 0.14 * highlight - 0.08 * depth * outerRim, 0.0, 1.0);
                color += float4(tint * alpha, alpha) * ringCoverage;
            }
        }
        color *= u.opacity;
        color.rgb *= u.tint;
    }
    if (carouselPromoted && u.shadowAlpha > 0) {
        float imageCoverage = 0;
        if (carouselShadowOnly) {
            // Image surfaces cover the native material independently. Match the
            // ordinary image silhouette without sampling its texture here.
            imageCoverage = coverage * u.opacity;
            // These pixels already had zero shadow alpha and reached the same
            // discard below. Calculate silhouette AA before skipping the falloff.
            if (imageCoverage >= 1) discard_fragment();
        }
        float sd = max(0.0, roundedDistance(local - u.shadowOffset, u.frameHalf, u.frameRadius));
        float shadow = u.shadowAlpha * exp(-sd * sd * u.shadowFalloff);
        if (carouselShadowOnly) {
            color.a = shadow * (1 - imageCoverage);
        } else {
            color.a += shadow * (1 - color.a);
        }
    }
    if (color.a < 0.0005) discard_fragment();
    if (carouselPromoted && u.occluderCount > 0 && u.occlusion > 0) {
        float c = u.rotation.x, s = u.rotation.y;
        float2 screen = u.center + float2(local.x * c - local.y * s, local.x * s + local.y * c);
        float reveal = 1;
        for (uint index = 0; index < u.occluderCount; ++index) {
            constant CarouselOccluderUniforms &occluder = occluders[index];
            float2 d = screen - occluder.center;
            float cosine = occluder.rotation.x, sine = occluder.rotation.y;
            float2 p = float2(d.x * cosine + d.y * sine, -d.x * sine + d.y * cosine);
            float distance = roundedDistance(p, occluder.cardSize * 0.5, occluder.cornerRadius);
            float aa = max(fwidth(distance), 0.35);
            float alpha = (1 - smoothstep(-aa * 0.5, aa * 0.5, distance)) * occluder.opacity;
            reveal *= 1 - u.occlusion * alpha;
        }
        color *= reveal;
    }
    return color;
}

// MARK: - 3D cards (CarouselConfiguration.Card3D)
//
// The cards as laminated plastic, after the onboarding project's cards: a paper sheet
// carrying the image, sealed in a clear plastic slab with the card's outline, its own
// thickness and an edge rounded by a superellipse bevel whose exact normal comes from
// the position. A margin of clear plastic runs from the paper's edge to the card's;
// through it, and through the edge, the carousel behind shows, by a second, per-channel
// blend output (dual-source blending). The light is a photo studio's, baked into two
// small cubes. One camera above the screen's centre lights every card, so a card's gloss
// slides across it as the wheel carries it. Inside the plastic a ray is refracted once,
// then straight: what shows behind a card is not displaced. Card space: origin at the
// card's centre, x right, y down, z toward the viewer; the face at z = 0, the back at
// z = -thickness. A card turned by `turn` about its vertical axis is seen from `distance`
// points above its centre, as Core Animation's m34 = -1/d shows its views.

/// Shared by every 3D card in a frame. Swift twin: CarouselSlabUniforms, 96 bytes.
struct CarouselSlabUniforms {
    float4 stock;          // rgb: linear colour of the paper where nothing is printed
    float4 absorption;     // rgb: the plastic's absorption per card width
    float4 eye;            // xyz: the camera lighting every card, in screen points, z toward the viewer
    float thicknessRatio;  // thickness over the card's outer width
    float bevelFraction;   // edge radius over thickness
    float exponent;        // edge profile |x|^e + |y|^e = 1
    float highlight;       // gloss weight
    float roughness;       // the plastic surface's roughness
    float maxLod;          // the studio cube's last mip level
    float marginRatio;     // clear margin over the card's outer width
    float aboveRatio;      // plastic above the paper, over the outer width
    float paperRatio;      // the paper's thickness, over the outer width
    float ior;             // the plastic's refractive index
    float lighting;        // CarouselCardLighting's index: the lights in front of the cards
    float lightAngle;      // those lights' turn about the screen's centre, radians clockwise
};

/// Optional pigment for the whole plastic card, in linear light. Swift twin:
/// CarouselCardColorUniforms, 96 bytes. None specialises away this buffer entirely.
struct CarouselCardColorUniforms {
    float4 color0;         // premultiplied linear RGB, opacity
    float4 color1;
    float4 color2;
    float4 parameters;     // strength, start position, middle fraction, end position
    float4 linearGeometry; // direction.xy, reciprocal L1 length, unused
    float4 radialGeometry; // centre.xy in half-card coordinates, radius, unused
};

static void carouselApplyCardColor(float2 point, float2 halfSize,
                                    constant CarouselCardColorUniforms &color,
                                    thread float3 &light, thread float3 &through) {
    float4 pigment = color.color1;
    if (carouselColorStyle == 2 || carouselColorStyle == 3) {
        // Coordinates belong to the physical card, so gradients follow holds,
        // tilts and flips with the same outline on the front and the back.
        float2 q = point / max(halfSize, float2(1));
        float t = carouselColorStyle == 2
            ? 0.5 + 0.5 * dot(q, color.linearGeometry.xy) * color.linearGeometry.z
            : length(q - color.radialGeometry.xy) / max(color.radialGeometry.z, 0.05);
        t = saturate((t - color.parameters.y) / max(color.parameters.w - color.parameters.y, 0.0001));
        float middle = clamp(color.parameters.z, 0.05, 0.95);
        // Mix alpha-premultiplied pigment before recovering its hue: a fully
        // transparent stop contributes no colour, including at its transition.
        pigment = mix(mix(color.color0, color.color1, saturate(t / middle)),
                       color.color2, saturate((t - middle) / (1 - middle)));
    }
    if (pigment.a <= 0.0) return;
    // A pigmented optical coat absorbs channels rather than filling the paper
    // with an opaque colour. Even at full strength, the original print's detail
    // and dark tones survive; the clear margin transmits the same coloured light.
    float amount = saturate(color.parameters.x) * saturate(pigment.a);
    float3 filter = mix(float3(1), 0.12 + 0.88 * clamp(pigment.rgb / pigment.a, 0.0, 1.0), amount);
    light *= filter;
    through *= filter;
}

struct CarouselSlabVertex {
    float4 position [[position]];
    float2 screen;         // offset from the card's centre before its in-plane tilt, points
};

/// What a 3D card adds over the drawable, and how much of the drawable it keeps.
struct CarouselSlabOutput {
    float4 color [[color(0), index(0)]];
    float4 transmission [[color(0), index(1)]];
};

// The quad's corners are offsets on screen from the card's centre. For a flat card they
// are its card-local corners, with the same arithmetic as carouselCardVertex, so a flat
// slab rasterises exactly like a flat card; a turning card's quad is its projected slab.
vertex CarouselSlabVertex carouselSlabVertex(uint vertexID [[vertex_id]],
                                             constant CarouselCardUniforms &u [[buffer(0)]]) {
    const float2 corners[] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 offset = u.quadCenter + corners[vertexID] * u.quadHalf;
    float c = u.rotation.x, s = u.rotation.y;
    float2 uv = (u.center + float2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)) / u.viewport;
    CarouselSlabVertex output;
    output.position = float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1);
    output.screen = offset;
    return output;
}

struct CarouselSlabShape {
    float2 halfSize;       // the outline's half size (the frame's, when there is one)
    float radius;          // the outline's corner radius
    float thickness;
    float bevel;
    float exponent;
    float distance;        // the eye's height above the card's centre
    float2 paperHalf;      // the paper, inside the clear margin
    float paperRadius;
    float paperTop;        // z of the paper's printed face
    float paperBottom;     // z of its back
    float3 sigma;          // the plastic's absorption per point
    float ior;
};

// CarouselSlab.build is its Swift twin.
static CarouselSlabShape carouselSlabShape(constant CarouselCardUniforms &u, constant CarouselSlabUniforms &slab) {
    CarouselSlabShape s;
    float width = 2 * u.frameHalf.x;
    s.halfSize = u.frameHalf;
    s.radius = u.frameRadius;
    s.thickness = slab.thicknessRatio * width;
    s.bevel = max(0.0, min(min(slab.bevelFraction * s.thickness, s.thickness * 0.5), 0.9 * u.frameRadius));
    s.exponent = slab.exponent;
    s.distance = 4 * max(u.frameHalf.x, u.frameHalf.y);
    float margin = min(max(slab.marginRatio * width, s.bevel), 0.5 * min(u.frameHalf.x, u.frameHalf.y));
    s.paperHalf = u.frameHalf - margin;
    s.paperRadius = max(u.frameRadius - margin, 0.0);
    s.paperTop = -slab.aboveRatio * width;
    s.paperBottom = s.paperTop - slab.paperRatio * width;
    s.sigma = slab.absorption.rgb / max(width, 1.0);
    s.ior = slab.ior;
    return s;
}

struct CarouselOutlinePoint {
    float inward;          // distance in from the outline (negative outside)
    float2 normal;         // the outline's outward normal there
};

// The outline's signed distance and normal: exact, since a rounded rectangle is convex.
static CarouselOutlinePoint carouselOutline(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    float2 side = select(float2(-1.0), float2(1.0), p >= 0.0);
    CarouselOutlinePoint o;
    if (q.x > 0.0 && q.y > 0.0) {
        float l = length(q);
        o.normal = q / max(l, 1e-6) * side;
        o.inward = radius - l;
    } else if (q.x > q.y) {
        o.normal = float2(side.x, 0.0);
        o.inward = radius - q.x;
    } else {
        o.normal = float2(0.0, side.y);
        o.inward = radius - q.y;
    }
    return o;
}

// How far a point lies outside the slab, in points. The slab is its core (the outline
// shrunk by the bevel radius, between the two bevels) grown by the bevel's superellipse,
// so this is the distance from the core in that superellipse's norm, less the radius:
// convex, exact for a round bevel, and never steep, so Newton steps from outside the
// slab converge on its surface without passing it.
static float carouselSlabOutside(float3 p, CarouselSlabShape s) {
    CarouselOutlinePoint o = carouselOutline(p.xy, s.halfSize, s.radius);
    float r = s.bevel;
    float across = max(r - o.inward, 0.0);
    float along = max(max(p.z + r, r - s.thickness - p.z), 0.0);
    float e = s.exponent;
    return powr(powr(across, e) + powr(along, e), 1.0 / e) - r;
}

// Its gradient: zero inside the core.
static float3 carouselSlabGradient(float3 p, CarouselSlabShape s) {
    CarouselOutlinePoint o = carouselOutline(p.xy, s.halfSize, s.radius);
    float r = s.bevel;
    float across = max(r - o.inward, 0.0);
    float top = p.z + r, back = r - s.thickness - p.z;
    float along = max(max(top, back), 0.0);
    float e = s.exponent;
    float norm = powr(powr(across, e) + powr(along, e), 1.0 / e);
    if (norm <= 1e-6) return float3(0.0);
    float outward = powr(across / norm, e - 1.0), upward = powr(along / norm, e - 1.0);
    return float3(o.normal * outward, top >= back ? upward : -upward);
}

// The slab's outward normal at a point on its surface (or near it), in card space.
static float3 carouselSlabNormal(float3 p, CarouselSlabShape s) {
    float3 g = carouselSlabGradient(p, s);
    if (dot(g, g) > 1e-12) return normalize(g);
    // Exactly on a sharp-edged slab's surface: the nearest of its planes.
    CarouselOutlinePoint o = carouselOutline(p.xy, s.halfSize, s.radius);
    float toTop = -p.z, toBack = p.z + s.thickness, toSide = max(o.inward, 0.0);
    if (toSide < min(toTop, toBack)) return float3(o.normal, 0.0);
    return float3(0.0, 0.0, toTop <= toBack ? 1.0 : -1.0);
}

// Where the ray from `eye` along `d` enters and leaves the slab's bounding box, grown by
// a point; it misses the box, and passes the slab by more than a point, when it would
// leave first. The entry lies outside the slab.
static float2 carouselSlabBox(float3 eye, float3 d, CarouselSlabShape s) {
    const float pad = 1.0;
    float3 lower = float3(-s.halfSize - pad, -s.thickness - pad);
    float3 upper = float3(s.halfSize + pad, pad);
    float3 inverse = 1.0 / select(d, float3(1e-9), abs(d) < 1e-9);
    float3 t0 = (lower - eye) * inverse, t1 = (upper - eye) * inverse;
    float3 near = min(t0, t1), far = max(t0, t1);
    return float2(max(max(near.x, near.y), max(near.z, 0.0)), min(min(far.x, far.y), far.z));
}

// The first point where the ray meets the slab, by Newton steps from `t` (outside it) up
// to `end`; false if it passes. `before` keeps the last step short of the ray's closest
// approach, for carouselSlabClosest.
static bool carouselSlabHit(float3 eye, float3 d, float end, thread float &t, thread float &before,
                            CarouselSlabShape s) {
    before = t;
    #pragma clang loop unroll(disable)
    for (int i = 0; i < 16; i++) {
        float f = carouselSlabOutside(eye + d * t, s);
        if (f < 1e-3) return true;
        float slope = dot(carouselSlabGradient(eye + d * t, s), d);
        if (slope > -1e-4) return false;
        before = t;
        t = min(t - f / slope, end);
    }
    return carouselSlabOutside(eye + d * t, s) < 1e-2;
}

// The slab's distance where the ray passes closest to it, between `low` (short of that
// point) and `high` (past it): negative when the ray goes through the slab. The distance
// is convex along the ray, so its slope changes sign once there: bisect on it.
static float carouselSlabClosest(float3 eye, float3 d, float low, float high, thread float &at,
                                 CarouselSlabShape s) {
    #pragma clang loop unroll(disable)
    for (int i = 0; i < 10; i++) {
        float mid = 0.5 * (low + high);
        if (dot(carouselSlabGradient(eye + d * mid, s), d) < 0) low = mid;
        else high = mid;
    }
    at = 0.5 * (low + high);
    return carouselSlabOutside(eye + d * at, s);
}

// Where the line o + d s crosses a circle: [in, out], empty (in > out) if it misses.
static float2 carouselCircleSpan(float2 o, float2 d, float2 center, float radius) {
    float2 oc = o - center;
    float a = dot(d, d), b = dot(oc, d), c = dot(oc, oc) - radius * radius;
    if (a < 1e-12) return c <= 0 ? float2(-1e9, 1e9) : float2(1, 0);
    float disc = b * b - a * c;
    if (disc < 0) return float2(1, 0);
    float root = sqrt(disc);
    return float2((-b - root) / a, (-b + root) / a);
}

// Where the line o + d s lies inside a rounded rectangle: [in, out], empty if in > out.
// It is the box's span, except that an end in a corner's square lies on that corner's
// circle instead (or the line misses: a corner square's inner sides lie inside its circle).
static float2 carouselRoundedRectSpan(float2 o, float2 d, float2 halfSize, float radius) {
    float2 inverse = 1.0 / select(d, float2(1e-9), abs(d) < 1e-9);
    float2 t0 = (-halfSize - o) * inverse, t1 = (halfSize - o) * inverse;
    float2 near = min(t0, t1), far = max(t0, t1);
    float2 span = float2(max(near.x, near.y), min(far.x, far.y));
    if (span.x > span.y || radius <= 0) return span;
    float2 inner = halfSize - radius;
    float2 a = o + d * span.x;
    if (abs(a.x) > inner.x && abs(a.y) > inner.y) {
        float2 corner = carouselCircleSpan(o, d, select(-inner, inner, a >= 0.0), radius);
        if (corner.x > corner.y) return float2(1, 0);
        span.x = corner.x;
    }
    float2 b = o + d * span.y;
    if (abs(b.x) > inner.x && abs(b.y) > inner.y) {
        float2 corner = carouselCircleSpan(o, d, select(-inner, inner, b >= 0.0), radius);
        if (corner.x > corner.y) return float2(1, 0);
        span.y = corner.y;
    }
    return span;
}

struct CarouselPaperHit {
    float along;           // how far along the ray the paper is, -1 if it is not met
    int face;              // 1 its printed face, -1 its back, 0 its edge
};

// Where a ray inside the plastic, from `o` along `d`, first meets the paper sheet.
static CarouselPaperHit carouselPaperHit(float3 o, float3 d, CarouselSlabShape s) {
    CarouselPaperHit hit;
    hit.along = -1;
    hit.face = 0;
    float2 depth;
    if (abs(d.z) > 1e-6) {
        float a = (s.paperTop - o.z) / d.z, b = (s.paperBottom - o.z) / d.z;
        depth = float2(min(a, b), max(a, b));
    } else if (o.z <= s.paperTop && o.z >= s.paperBottom) {
        depth = float2(-1e9, 1e9);
    } else {
        return hit;
    }
    float2 span = carouselRoundedRectSpan(o.xy, d.xy, s.paperHalf, s.paperRadius);
    float enter = max(max(depth.x, span.x), 0.0), leave = min(depth.y, span.y);
    if (enter > leave) return hit;
    hit.along = enter;
    hit.face = depth.x >= span.x ? (d.z < 0 ? 1 : -1) : 0;
    return hit;
}

// MARK: Studio

// A soft rectangular light seen through a gnomonic projection around its centre.
static float carouselSoftbox(float3 d, float3 center, float3 up, float2 halfSize, float softness) {
    float3 c = normalize(center);
    float3 right = normalize(cross(c, up));
    float3 u = cross(right, c);
    float z = dot(d, c);
    if (z <= 0.0) return 0.0;
    float2 q = abs(float2(dot(d, right), dot(d, u)) / z);
    float2 edge = 1.0 - smoothstep(halfSize - softness, halfSize + softness, q);
    return edge.x * edge.y;
}

// Linear radiance around the cards, in the screen's frame (y down, z toward the viewer):
// dim surroundings, so a face reflects mostly darkness and keeps its print's colours, and
// lights that catch the edges and turning faces: a key softbox (upper left), a tall strip
// (right), and lights above and behind. The gloss lights in front of the cards are
// evaluated exactly per pixel instead (carouselGlossLights): a cube's texels would blur them.
static float3 carouselStudio(float3 d) {
    float up = -d.y;
    float3 color = mix(float3(0.012, 0.012, 0.014), float3(0.06, 0.06, 0.065), saturate(up * 0.5 + 0.5));
    color += float3(6.0, 5.9, 5.7) * carouselSoftbox(d, float3(-0.45, -0.55, 0.70), float3(0, -1, 0), float2(0.22, 0.34), 0.08);
    color += float3(4.0, 4.1, 4.3) * carouselSoftbox(d, float3(0.62, -0.05, 0.78), float3(0, -1, 0), float2(0.06, 0.7), 0.03);
    color += float3(2.0, 2.0, 2.1) * carouselSoftbox(d, float3(0.0, -0.9, -0.43), float3(0, 0, -1), float2(0.9, 0.5), 0.3);
    color += float3(0.8, 0.84, 0.88) * carouselSoftbox(d, float3(0.0, 0.2, -1.0), float3(0, -1, 0), float2(1.2, 0.7), 0.4);
    return color;
}

// A thin ring of light around `center`, in the gnomonic plane of the view axis.
static float carouselRingLight(float2 g, float2 center, float radius, float halfWidth, float blur) {
    float away = abs(length(g - center) - radius);
    return 1.0 - smoothstep(halfWidth - blur, halfWidth + blur, away);
}

// Behind the viewer, above the screen's centre: the lights flat faces mirror, chosen by
// `slab.lighting` (CarouselCardLighting) and turned about the screen's centre by
// `slab.lightAngle`. Far brighter than the cards' diffuse light, so their 4% reflection
// reads as gloss; they stay put on the screen while the wheel carries each card through
// them. Their edges widen with the surface's roughness. A light at gnomonic (x, y) shows
// on screen about 1.2 × the view's larger side times (x, y) from its centre.
static float3 carouselGlossLights(float3 r, float roughness, constant CarouselSlabUniforms &slab) {
    if (r.z <= 0.0) return 0.0;
    float c = cos(slab.lightAngle), s = sin(slab.lightAngle);
    r = float3(r.x * c + r.y * s, -r.x * s + r.y * c, r.z);
    float2 g = r.xy / r.z;
    float blur = 0.004 + 0.3 * roughness * roughness;
    const float3 up = float3(0, -1, 0);
    const float3 diagonal = float3(0.42, -0.91, 0.0);
    int lighting = int(slab.lighting + 0.5);
    float3 light = 0.0;
    switch (lighting) {
        case 1: {
            // A four-pane window, upper left, its bars dark across it, with a faint bloom.
            float pane = carouselSoftbox(r, float3(-0.10, -0.13, 1.0), up, float2(0.13, 0.09), blur + 0.006);
            float2 q = abs(g - float2(-0.10, -0.13));
            float bars = min(smoothstep(0.004, 0.007 + blur, q.x), smoothstep(0.004, 0.007 + blur, q.y));
            light = float3(8.0, 7.9, 7.6) * pane * bars + float3(0.9, 0.9, 0.92) *
                carouselSoftbox(r, float3(-0.10, -0.13, 1.0), up, float2(0.17, 0.13), 0.08);
            break;
        }
        case 2: {
            // Three tall studio strips.
            light = float3(12.0, 11.9, 11.6) * carouselSoftbox(r, float3(-0.17, -0.05, 1.0), up, float2(0.006, 0.6), blur);
            light += float3(9.0, 9.0, 9.1) * carouselSoftbox(r, float3(-0.02, -0.05, 1.0), up, float2(0.004, 0.6), blur);
            light += float3(12.0, 11.9, 11.6) * carouselSoftbox(r, float3(0.14, -0.05, 1.0), up, float2(0.006, 0.6), blur);
            break;
        }
        case 3: {
            // Sky over a dark floor: the horizon a little above the wheel, the sky brighter higher up.
            float sky = 1.0 - smoothstep(-0.03 - blur - 0.004, -0.03 + blur + 0.004, g.y);
            light = float3(3.3, 3.5, 4.0) * sky * (0.55 + 0.45 * smoothstep(-0.03, -0.35, g.y));
            light += float3(9.0, 8.6, 7.8) * carouselSoftbox(r, float3(-0.13, -0.16, 1.0), up, float2(0.02, 0.02), blur + 0.012);
            break;
        }
        case 4: {
            // A ring light.
            light = float3(12.0, 11.9, 11.8) * carouselRingLight(g, float2(0.0, -0.08), 0.11, 0.008, blur);
            break;
        }
        case 5: {
            // Through an iridescent film: the streak and a window, with a faint rainbow wash.
            float3 tint = 0.55 + 0.45 * cos(6.2831853 * (2.2 * (g.x - 0.6 * g.y) + float3(0.0, 0.33, 0.67)));
            float3 lights = float3(12.0) * carouselSoftbox(r, float3(-0.064, -0.115, 1.0), diagonal, float2(0.006, 0.5), blur);
            lights += float3(5.0) * carouselSoftbox(r, float3(0.12, -0.16, 1.0), up, float2(0.06, 0.04), blur + 0.02);
            light = tint * (lights + 1.6);
            break;
        }
        case 6:
            break;
        default: {
            // The diagonal strip, a softer glow beside it, and a small soft lamp.
            light = float3(15.0, 14.9, 14.5) * carouselSoftbox(r, float3(-0.064, -0.115, 0.991), diagonal, float2(0.005, 0.5), blur);
            light += float3(4.5, 4.5, 4.6) * carouselSoftbox(r, float3(-0.03, -0.11, 0.993), diagonal, float2(0.024, 0.5), 2.0 * blur);
            light += float3(6.0, 5.95, 5.8) * carouselSoftbox(r, float3(0.12, -0.16, 0.98), up, float2(0.03, 0.02), blur + 0.03);
            break;
        }
    }
    return light;
}

static float3 carouselCubeDirection(uint face, float2 uv) {
    switch (face) {
        case 0: return normalize(float3(1.0, -uv.y, -uv.x));
        case 1: return normalize(float3(-1.0, -uv.y, uv.x));
        case 2: return normalize(float3(uv.x, 1.0, uv.y));
        case 3: return normalize(float3(uv.x, -1.0, -uv.y));
        case 4: return normalize(float3(uv.x, -uv.y, 1.0));
        default: return normalize(float3(-uv.x, -uv.y, -1.0));
    }
}

static float2 carouselHammersley(uint i, uint count) {
    return float2(float(i) / float(count), float(reverse_bits(i)) * 2.3283064365386963e-10);
}

static float3 carouselTangentToWorld(float3 v, float3 n) {
    float3 up = abs(n.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangentX = normalize(cross(up, n));
    float3 tangentY = cross(n, tangentX);
    return tangentX * v.x + tangentY * v.y + n * v.z;
}

// One mip level of the studio, prefiltered for one roughness with GGX importance
// sampling around the reflection (N = V = R); roughness 0 is the studio itself.
kernel void carouselStudioPrefilter(texturecube<half, access::write> output [[texture(0)]],
                                    constant float &roughness [[buffer(0)]],
                                    uint3 gid [[thread_position_in_grid]]) {
    uint size = output.get_width();
    if (gid.x >= size || gid.y >= size || gid.z >= 6) return;
    float3 n = carouselCubeDirection(gid.z, (float2(gid.xy) + 0.5) / float(size) * 2.0 - 1.0);
    if (roughness <= 0.0) {
        output.write(half4(half3(carouselStudio(n)), 1.0h), gid.xy, gid.z);
        return;
    }
    float a = roughness * roughness;
    const uint count = 512;
    float3 sum = 0.0;
    float weight = 0.0;
    for (uint i = 0; i < count; i++) {
        float2 xi = carouselHammersley(i, count);
        float phi = 2.0 * M_PI_F * xi.x;
        float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        float3 h = carouselTangentToWorld(float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta), n);
        float3 l = 2.0 * dot(n, h) * h - n;
        float nol = dot(n, l);
        if (nol > 0.0) {
            sum += carouselStudio(l) * nol;
            weight += nol;
        }
    }
    output.write(half4(half3(sum / max(weight, 1e-4)), 1.0h), gid.xy, gid.z);
}

constant float3 carouselKeyLight = float3(-0.45, -0.55, 0.70);
constant float carouselKeyIlluminance = 1.2;

static float carouselStudioLight(float3 n) {
    const uint count = 1024;
    float3 sum = 0.0;
    for (uint i = 0; i < count; i++) {
        float2 xi = carouselHammersley(i, count);
        float phi = 2.0 * M_PI_F * xi.x;
        float cosTheta = sqrt(1.0 - xi.y);
        float sinTheta = sqrt(xi.y);
        sum += carouselStudio(carouselTangentToWorld(float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta), n));
    }
    float3 average = sum / float(count);
    return dot(average, float3(0.2126, 0.7152, 0.0722)) +
        carouselKeyIlluminance / M_PI_F * saturate(dot(n, normalize(carouselKeyLight)));
}

// The diffuse light on a face looking at the screen, which the cube is relative to.
kernel void carouselStudioReference(device float &reference [[buffer(0)]],
                                    uint gid [[thread_position_in_grid]]) {
    if (gid == 0) reference = carouselStudioLight(float3(0, 0, 1));
}

// The diffuse light on a surface facing each direction, relative to a face looking at
// the screen: exactly 1 there (the centre texel of the +z face of an odd-sized cube), so
// the paper's print keeps its colours when the card faces the screen.
kernel void carouselStudioIrradiance(texturecube<half, access::write> output [[texture(0)]],
                                     constant float &reference [[buffer(0)]],
                                     uint3 gid [[thread_position_in_grid]]) {
    uint size = output.get_width();
    if (gid.x >= size || gid.y >= size || gid.z >= 6) return;
    if (gid.z == 4 && gid.x == size / 2 && gid.y == size / 2 && size % 2 == 1) {
        output.write(half4(1.0h), gid.xy, gid.z);
        return;
    }
    float3 n = carouselCubeDirection(gid.z, (float2(gid.xy) + 0.5) / float(size) * 2.0 - 1.0);
    output.write(half4(half(carouselStudioLight(n) / max(reference, 1e-4))), gid.xy, gid.z);
}

// MARK: Light

static float carouselMaterialRoughness(float roughness) {
    if (carouselFrosted) return max(roughness, 0.34);
    if (carouselSmoked) return max(roughness, 0.18);
    return roughness;
}

// A finish changes the clear coat's reflection, never the texture printed below
// it. Prismatic interference is restricted to grazing angles; neutral transmitted
// colours remain neutral because dispersion is sampled separately at the margin.
static float3 carouselMaterialReflection(float3 reflection, float nov, float3 normal) {
    if (carouselSmoked) return reflection * float3(0.76, 0.86, 0.98);
    if (carouselPrismatic) {
        float grazing = 1 - smoothstep(0.25, 0.88, saturate(nov));
        float phase = 2.6 * nov + dot(normal.xy, float2(0.7, -0.45));
        float3 film = 0.78 + 0.22 * cos(6.2831853 * (phase + float3(0.0, 0.3333333, 0.6666667)));
        return reflection * mix(float3(1), film * 1.22, 0.7 * grazing);
    }
    return reflection;
}

static float2 carouselEnvironmentBRDF(float roughness, float nov) {
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * nov)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}

// Filament's normal filtering: the roughness widened by how fast the normal turns across
// the pixel, so the edge's reflection never sparkles.
static float carouselFilteredRoughness(float perceptualRoughness, float normalChange) {
    float kernelRoughness = min(2.0 * 0.15 * normalChange, 0.2);
    float roughness = perceptualRoughness * perceptualRoughness;
    return sqrt(sqrt(saturate(roughness * roughness + kernelRoughness)));
}

// Unpolarised Fresnel reflectance of a smooth dielectric interface, for light arriving
// at `cosIncident` on the side of index n1, with `eta` = n1 / n2; 1 past the critical angle.
static float carouselFresnel(float cosIncident, float eta) {
    float cosI = saturate(cosIncident);
    float sinT2 = eta * eta * (1.0 - cosI * cosI);
    if (sinT2 >= 1.0) return 1.0;
    float cosT = sqrt(1.0 - sinT2);
    float rs = (eta * cosI - cosT) / (eta * cosI + cosT);
    float rp = (cosI - eta * cosT) / (cosI + eta * cosT);
    return 0.5 * (rs * rs + rp * rp);
}

// A broad shoulder under the chosen studio lights gives the surface a soft optical
// roll-off rather than another hard white streak. Its view is still the single studio
// camera shared by every card, so highlights travel across the wheel coherently.
static float3 carouselRefinedGloss(float3 r, float roughness, constant CarouselSlabUniforms &slab) {
    float3 light = carouselGlossLights(r, max(roughness, 0.085), slab);
    if (r.z <= 0.0 || int(slab.lighting + 0.5) == 6) return light;
    float c = cos(slab.lightAngle), s = sin(slab.lightAngle);
    float3 turned = float3(r.x * c + r.y * s, -r.x * s + r.y * c, r.z);
    float shoulder = carouselSoftbox(turned, float3(-0.11, -0.18, 1), float3(0, -1, 0),
                                     float2(0.24, 0.15), 0.11 + roughness * 0.12);
    return light * 0.78 + float3(1.10, 1.07, 1.01) * shoulder;
}

static float3 carouselRefinedReflection(float3 radiance, float roughness, float nov, float f0,
                                        constant CarouselSlabUniforms &slab) {
    float2 ab = carouselEnvironmentBRDF(roughness, nov);
    float reflectance = saturate(f0 * ab.x + ab.y);
    // Compress bright lamps smoothly before reflection. The print remains readable
    // under a strip, while grazing edges retain the dielectric's Fresnel rise.
    float3 exposed = max(radiance, float3(0));
    exposed /= 1 + exposed * 0.20;
    return exposed * min(1.0, slab.highlight * reflectance);
}

// Restrained diffuse light on the buried sheet. Direction and the broad falloff live
// in screen space, matching the studio; the contour darkens only the paper/plastic
// contact, never the image's centre or the transparent margin.
static float carouselPaperLight(float3 normal, float2 worldOffset, float width,
                                 float irradiance, float paperDistance, float2 rim, float pixel) {
    float3 key = normalize(carouselKeyLight);
    float directional = clamp(0.92 + 0.08 * dot(normal, key) / key.z, 0.80, 1.03);
    float broad = clamp(0.995 - 0.025 * dot(worldOffset / max(width, 1.0), float2(0.6, 0.8)), 0.97, 1.015);
    float contact = exp(-max(-paperDistance, 0.0) / max(0.7, pixel));
    float lower = saturate(dot(rim, float2(0.6, 0.8)));
    return mix(1.0, clamp(irradiance, 0.65, 1.25), 0.35) * directional * broad *
        (1 - (0.025 + 0.045 * lower) * contact);
}

// The sharp contour and its wider, softer shoulder are independent. The opposite
// studio lobe is cool and quieter; a fine lower contour lends depth without drawing
// a frame. Only this optical border attenuates the drawable transmitted through it.
static void carouselLaminateRim(float distance, float bevel, float pixel, float2 rim,
                                float nov, constant CarouselSlabUniforms &slab,
                                thread float3 &light, thread float3 &through) {
    float inward = max(-distance, 0.0);
    float sharpWidth = max(0.55 * pixel, 0.38);
    float softWidth = max(1.1 * pixel, min(bevel * 1.65, 3.5));
    float sharp = 1 - smoothstep(0.0, sharpWidth, inward);
    float soft = 1 - smoothstep(0.0, softWidth, inward);
    float c = cos(slab.lightAngle), s = sin(slab.lightAngle);
    float2 key = float2(-0.6 * c + 0.8 * s, -0.6 * s - 0.8 * c);
    float facing = dot(rim, key);
    float keyLobe = powr(saturate(facing), 1.6);
    float fillLobe = powr(saturate(-facing), 2.0);
    float fresnel = 0.04 + 0.96 * powr(1 - saturate(nov), 5.0);
    float energy = min(slab.highlight, 1.5);
    float3 glint = float3(1.0, 0.965, 0.91) * keyLobe * (0.085 * sharp + 0.036 * soft);
    glint += float3(0.80, 0.90, 1.0) * fillLobe * (0.025 * sharp + 0.018 * soft);
    float shade = (0.018 + 0.026 * fillLobe) * soft;
    light = light * (1 - shade) + glint * (0.65 + 0.35 * fresnel) * energy;
    through *= float3(1 - shade) - float3(0.010, 0.003, 0.001) * soft * fillLobe;
}

// A finite Gaussian-like blurred step, reconstructed by the reference demo from
// QuartzCore. Signed distance gives a half-strength penumbra at the contour instead
// of the legacy falloff's opaque plateau outside the silhouette.
static float carouselShadowProfile(float distance, float radius) {
    float x = clamp(distance / (max(radius, 0.25) * 1.41421356237), -2.0, 2.0);
    float x2 = x * x;
    return saturate(0.5 + x * (-0.560546875 + x2 * (0.168212890625 +
        x2 * (-0.034454345703125 + x2 * 0.0029544830322265625))));
}

static float carouselLayeredShadow(float2 p, constant CarouselCardUniforms &u) {
    float radius = rsqrt(max(2 * u.shadowFalloff, 1e-6));
    float contactDistance = roundedDistance(p - u.shadowOffset * 0.25, u.frameHalf, u.frameRadius);
    float softDistance = roundedDistance(p - u.shadowOffset, u.frameHalf, u.frameRadius);
    float contact = carouselShadowProfile(contactDistance, radius * 0.28) * u.shadowAlpha * 0.55;
    float penumbra = carouselShadowProfile(softDistance, radius) * u.shadowAlpha * 0.75;
    return 1 - (1 - contact) * (1 - penumbra);
}

/// A 3D card's back video (`CardCarousel.cardBackVideo`): its panel in the points of the
/// back view, and how much of the video fills it along each axis (aspect fill). A zero
/// `backSize` shows none. Swift twin: CarouselBackVideoUniforms, 48 bytes.
struct CarouselBackVideoUniforms {
    float2 backSize;
    float2 panelCenter;
    float2 panelHalf;
    float2 fit;
    float radius;
    float padding0;
    float padding1;
    float padding2;
};

/// A card near a 3D card, whose colours bleed into its edge (`Card3D.bleed`). Swift twin:
/// CarouselBleedNeighbour, 48 bytes.
struct CarouselBleedNeighbour {
    float2 center;
    float2 rotation;
    float2 halfSize;       // its image's
    float2 uvScale;        // its image, aspect-filled; a negative x mirrors a back face
    float radius;          // its outline's corner radius
    float opacity;         // its opacity, times its dimming
    float lodBias;         // log2 of its image's texels per point
    float padding;
};

/// Swift twin: CarouselBleedUniforms, 208 bytes.
struct CarouselBleedUniforms {
    uint count;            // neighbours, in draw order; 0 turns the bleed off
    float strength;        // its weight at the card's edge
    float height;          // how deep it reaches into the card, and how far out it looks, points
    float blur;            // the blur of what it sees there, points
    CarouselBleedNeighbour neighbours[4];
};

/// Opaque paper above a source face in the promoted stack. Swift: 48 bytes.
struct CarouselRefractionMask {
    float2 center;
    float2 rotation;
    float2 paperHalf;
    float2 turn;
    float distance;
    float depth;
    float radius;
    float opacity;
};

/// Actual printed source geometry, present only with improved refraction. Swift: 448 bytes.
struct CarouselRefractionNeighbour {
    float2 imageHalf;
    float2 paperHalf;
    float2 uvScale;
    float2 turn;
    float distance;
    float depth;
    float paperRadius;
    float imageRadius;
    float lodBias;
    float foreground;
    float occlusion;
    uint occluderCount;
    CarouselBackVideoUniforms video;
    CarouselOccluderUniforms occluders[4];
    uint promotedMaskCount;
    float padding0;
    float padding1;
    float padding2;
    CarouselRefractionMask promotedMasks[4];
};

/// Swift: 1792 bytes. The original bleed uniforms and their shader path stay independent.
struct CarouselRefractionUniforms {
    CarouselRefractionNeighbour neighbours[4];
};

/// Screen-visible paper radiance on an actual shared-scene plane. Swift: 192 bytes.
struct CarouselSceneSource {
    float4x4 sceneToSlab;
    float2 imageHalf;
    float2 paperHalf;
    float2 uvScale;
    float paperRadius;
    float imageRadius;
    float depth;
    float opacity;
    float lodBias;
    float tint;
    uint index;
    float margin;
    CarouselBackVideoUniforms video;
    float2 radiance; // visible-face fade; 1 + wheel occlusion for promoted sources
    uint visibilityMask;
    float outerRadius;
};

/// Swift: 1696 bytes. All matrices describe actual volumes in one scene camera.
struct CarouselSceneUniforms {
    float4x4 receiverToScene;
    float4x4 sceneToReceiver;
    float4 eye; // xyz camera position; w source radiance strength
    uint count;
    uint receiverIndex;
    float2 beam; // finite broad-beam depth in world points; reserved
    CarouselSceneSource sources[8];
};

// Liquid Glass's edge bleed (macOS 27's edge_bleed, as the gpui-glass demo's research
// decodes it): a point `d` inside the outline (negative inside) looks outward along the
// outline's normal `n`, furthest at the contour and not at all `height` deep, at what is
// around the card, blurred, and takes its colour, most at the edge (band²). Here what is
// around a card is only its neighbours: each one's image at a coarse mip, where it covers
// that point (its edge blurred too), stacked in draw order. The card itself and the
// background never bleed. Returns the colour, and its weight in `a`.
static float4 carouselBleed(float2 screen, float d, float2 n, float pixel, float sampleFootprint,
                            float clearPlastic,
                            constant CarouselBleedUniforms &bleed,
                            array<texture2d<float>, 4> images, sampler sampling) {
    uint count = min(bleed.count, 4u);
    if (count == 0 || bleed.strength <= 0) return 0;
    float t = saturate(-d / max(bleed.height, 1.0));
    float2 s = screen + bleed.height * (1.0 - sqrt(t * (2.0 - t))) * n;
    float sampleBlur = bleed.blur;
    if (carouselRefractiveEdges) {
        // The reference keeps lens sampling separate from its colour/tone response.
        // Keep the displaced source's detail at the contour, then soften it inward.
        // Integrate the circular profile across a pixel: its rapidly expanding ray
        // footprint at the silhouette still chooses an antialiased mip.
        float step = pixel / max(bleed.height, 1.0);
        float a = saturate(t - 0.5 * step), b = saturate(t + 0.5 * step);
        float footprint = pixel + bleed.height * (sqrt(b * (2 - b)) - sqrt(a * (2 - a)));
        float sharpBlur = max(0.5 * footprint, min(2.0, max(0.8, bleed.blur * 0.16)));
        sampleBlur = max(sampleFootprint, mix(sharpBlur, bleed.blur, smoothstep(0.0, 0.65, t)));
    }
    if (carouselFrosted) {
        // Frost diffuses the rays crossing clear plastic. Rays ending on the
        // paper retain the chosen sharp refraction and the original artwork.
        sampleBlur = mix(sampleBlur, max(sampleBlur, max(4.0, bleed.blur * 0.70)), clearPlastic);
    }
    float3 premultiplied = 0;
    float alpha = 0;
    for (uint i = 0; i < count; i++) {
        constant CarouselBleedNeighbour &k = bleed.neighbours[i];
        float2 delta = s - k.center;
        float2 q = float2(delta.x * k.rotation.x + delta.y * k.rotation.y, -delta.x * k.rotation.y + delta.y * k.rotation.x);
        float cover = (1 - smoothstep(-bleed.blur, bleed.blur, roundedDistance(q, k.halfSize, k.radius))) * k.opacity;
        if (cover <= 0.001) continue;
        float2 uv = clamp(q, -k.halfSize, k.halfSize) * k.uvScale + 0.5;
        float lod = max(0.0, k.lodBias + log2(max(sampleBlur, 1.0)));
        float4 seen = images[i].sample(sampling, uv, level(lod));
        if (carouselSmoked) {
            seen.rgb *= mix(float3(1), float3(0.68, 0.76, 0.82), clearPlastic);
        }
        if (carouselPrismatic && clearPlastic > 0.001) {
            // Split the transmitted ray as the reference's Prism preset does.
            // One source per channel keeps constant white/grey energy unchanged;
            // only spatial detail separates into a spectral fringe.
            float2 split = n * (0.6 + min(0.9, bleed.height * 0.025)) * (1 - t) * (1 - t) * clearPlastic;
            float2 inCard = float2(split.x * k.rotation.x + split.y * k.rotation.y,
                                     -split.x * k.rotation.y + split.y * k.rotation.x);
            float2 redUV = clamp(q - inCard, -k.halfSize, k.halfSize) * k.uvScale + 0.5;
            float2 blueUV = clamp(q + inCard, -k.halfSize, k.halfSize) * k.uvScale + 0.5;
            float4 red = images[i].sample(sampling, redUV, level(lod));
            float4 blue = images[i].sample(sampling, blueUV, level(lod));
            seen.rgb = float3(red.r / max(red.a, 1e-4), seen.g / max(seen.a, 1e-4),
                              blue.b / max(blue.a, 1e-4)) * seen.a;
        }
        premultiplied = premultiplied * (1 - cover) + seen.rgb / max(seen.a, 1e-4) * cover;
        alpha = alpha * (1 - cover) + cover;
    }
    float band = 1.0 - t;
    return float4(premultiplied / max(alpha, 1e-4), alpha * bleed.strength * band * band);
}

struct CarouselNeighbourPoint {
    float2 local;
    float footprint;
    bool valid;
};

// Invert the same perspective and vertical turn used by the slab's eye ray. The
// analytic Jacobian supplies a mip footprint without derivatives after rejection.
static CarouselNeighbourPoint carouselProjectedPaperPoint(float2 screen, float2 center, float2 rotation,
                                                           float2 turn, float distance, float depth) {
    float2 delta = screen - center;
    float2 p = float2(dot(delta, rotation), -delta.x * rotation.y + delta.y * rotation.x);
    float c = turn.x, sn = turn.y, d = max(distance, 1.0);
    float denominator = c - p.x * sn / d;
    CarouselNeighbourPoint point = {float2(0), 1, false};
    // An edge-on face has no useful printed area. Keep rejected rays finite.
    if (abs(c) < 0.025 || abs(denominator) < 0.02) return point;
    float x = (p.x * (1 - depth * c / d) - depth * sn) / denominator;
    float w = 1 + (x * sn - depth * c) / d;
    float2 q = float2(x, p.y * w);
    if (w <= 0.02 || any(abs(q) > float2(1e5))) return point;
    float dx = abs((c - depth / d) / (denominator * denominator));
    point.local = q;
    point.footprint = max(dx * (1 + abs(p.y * sn / d)), abs(w));
    point.valid = true;
    return point;
}

static CarouselNeighbourPoint carouselNeighbourPoint(float2 screen,
                                                       constant CarouselBleedNeighbour &k,
                                                       constant CarouselRefractionNeighbour &source) {
    return carouselProjectedPaperPoint(screen, k.center, k.rotation, source.turn, source.distance, source.depth);
}

static float2 carouselNeighbourScreen(float2 q, constant CarouselBleedNeighbour &k,
                                       constant CarouselRefractionNeighbour &source) {
    float c = source.turn.x, sn = source.turn.y, d = max(source.distance, 1.0);
    float w = max(0.02, 1 + (q.x * sn - source.depth * c) / d);
    float2 p = float2(q.x * c + source.depth * sn, q.y) / w;
    return k.center + float2(p.x * k.rotation.x - p.y * k.rotation.y,
                             p.x * k.rotation.y + p.y * k.rotation.x);
}

static float carouselNeighbourVisibility(float2 screen, float pixel,
                                           constant CarouselRefractionNeighbour &source) {
    float visible = 1;
    for (uint j = 0; j < min(source.occluderCount, 4u); j++) {
        constant CarouselOccluderUniforms &occluder = source.occluders[j];
        float2 delta = screen - occluder.center;
        float2 q = float2(dot(delta, occluder.rotation),
                           -delta.x * occluder.rotation.y + delta.y * occluder.rotation.x);
        float distance = roundedDistance(q, occluder.cardSize * 0.5, occluder.cornerRadius);
        float alpha = (1 - smoothstep(-pixel * 0.5, pixel * 0.5, distance)) * occluder.opacity;
        visible *= 1 - source.occlusion * alpha;
    }
    for (uint j = 0; j < min(source.promotedMaskCount, 4u); j++) {
        constant CarouselRefractionMask &mask = source.promotedMasks[j];
        CarouselNeighbourPoint point = carouselProjectedPaperPoint(screen, mask.center, mask.rotation,
                                                                    mask.turn, mask.distance, mask.depth);
        if (!point.valid) continue;
        float aa = max(pixel * point.footprint, 0.35);
        float distance = roundedDistance(point.local, mask.paperHalf, mask.radius);
        float alpha = (1 - smoothstep(-aa * 0.5, aa * 0.5, distance)) * mask.opacity;
        visible *= 1 - alpha;
    }
    return visible;
}

// A transparent print is composited onto its actual paper, as in the slab's own
// face shader. Glass outside the paper contributes no opaque neighbour colour.
static float3 carouselNeighbourColour(float2 q, float lod, float pixel,
                                        constant CarouselRefractionNeighbour &source,
                                        texture2d<float> image, texture2d<float> videoImage,
                                        sampler sampling, float3 stock) {
    float2 uv = q * source.uvScale + 0.5;
    float4 picture = image.sample(sampling, uv, level(lod));
    if (source.uvScale.x < 0) {
        if (source.video.backSize.x > 0) {
            float2 inBack = uv * source.video.backSize - source.video.panelCenter;
            float inside = 1 - smoothstep(-0.6, 0.6,
                roundedDistance(inBack, source.video.panelHalf, source.video.radius));
            float2 seen = inBack / max(2 * source.video.panelHalf, float2(1)) * source.video.fit + 0.5;
            picture = mix(picture, float4(videoImage.sample(sampling, seen, level(0)).rgb, 1), inside);
        }
        return picture.rgb + stock * (1 - picture.a);
    }
    float distance = roundedDistance(q, source.imageHalf, source.imageRadius);
    float coverage = 1 - smoothstep(-pixel * 0.5, pixel * 0.5, distance);
    return picture.rgb * coverage + stock * (1 - picture.a * coverage);
}

// Depth OFF retains the original artistic front-image field, filling the blurred
// outer silhouette. Depth ON instead integrates actual shared-scene paper hits.
static float2 carouselNeighbourFrontFieldHalf(constant CarouselBleedNeighbour &neighbour,
                                               constant CarouselRefractionNeighbour &source) {
    return float2(neighbour.halfSize.x / max(abs(source.turn.x), 0.05), neighbour.halfSize.y);
}

static float3 carouselNeighbourFrontFieldColour(float2 q, float lod,
                                                 constant CarouselBleedNeighbour &neighbour,
                                                 constant CarouselRefractionNeighbour &source,
                                                 texture2d<float> image, sampler sampling, float3 stock) {
    float2 halfSize = carouselNeighbourFrontFieldHalf(neighbour, source);
    float2 uv = clamp(q, -halfSize, halfSize) * neighbour.uvScale + 0.5;
    float4 picture = image.sample(sampling, uv, level(lod));
    return picture.rgb + stock * (1 - picture.a);
}

static float4 carouselRefraction(float2 screen, float d, float2 n, float pixel, float sampleFootprint,
                                  float clearPlastic, float nov,
                                  constant CarouselBleedUniforms &bleed,
                                  constant CarouselRefractionUniforms &refraction,
                                  array<texture2d<float>, 4> images,
                                  array<texture2d<float>, 4> videos, sampler sampling, float3 stock) {
    uint count = min(bleed.count, 4u);
    if (count == 0 || bleed.strength <= 0) return 0;
    float t = saturate(-d / max(bleed.height, 1.0));
    float2 s = screen + bleed.height * (1 - sqrt(t * (2 - t))) * n;
    float step = pixel / max(bleed.height, 1.0);
    float a = saturate(t - 0.5 * step), b = saturate(t + 0.5 * step);
    float footprint = pixel + bleed.height * (sqrt(b * (2 - b)) - sqrt(a * (2 - a)));
    float sharpBlur = max(0.5 * footprint, min(2.0, max(0.8, bleed.blur * 0.16)));
    float sampleBlur = max(sampleFootprint, mix(sharpBlur, bleed.blur, smoothstep(0.0, 0.65, t)));
    if (carouselFrosted) sampleBlur = mix(sampleBlur, max(sampleBlur, max(4.0, bleed.blur * 0.70)), clearPlastic);
    float3 premultiplied = 0;
    float alpha = 0;
    for (uint i = 0; i < count; i++) {
        constant CarouselBleedNeighbour &k = bleed.neighbours[i];
        constant CarouselRefractionNeighbour &source = refraction.neighbours[i];
        CarouselNeighbourPoint point = carouselNeighbourPoint(s, k, source);
        if (!point.valid) continue;
        float sourcePixel = max(pixel * point.footprint, 0.35);
        bool frontField = source.uvScale.x >= 0;
        float2 halfSize = frontField ? carouselNeighbourFrontFieldHalf(k, source) : source.paperHalf;
        float distance = roundedDistance(point.local, halfSize, frontField ? k.radius : source.paperRadius);
        float blur = frontField ? max(bleed.blur, sourcePixel * 0.5) : sourcePixel * 0.5;
        float direct = 1 - smoothstep(-blur, blur, distance);
        float directVisibility = carouselNeighbourVisibility(
            carouselNeighbourScreen(point.local, k, source), pixel, source);
        direct *= directVisibility;
        float cover = direct * k.opacity;
        if (cover <= 0.001) continue;
        float sourceBlur = frontField ? bleed.blur : sampleBlur;
        if (carouselFrosted) sourceBlur = mix(sourceBlur, max(sourceBlur, max(4.0, bleed.blur * 0.70)), clearPlastic);
        float lod = max(0.0, (frontField ? k.lodBias : source.lodBias) + log2(max(sourceBlur * point.footprint, 1.0)));
        float3 seen = frontField ? carouselNeighbourFrontFieldColour(point.local, lod, k, source, images[i], sampling, stock) :
            carouselNeighbourColour(point.local, lod, sourcePixel, source, images[i], videos[i], sampling, stock);
        if (carouselSmoked) seen *= mix(float3(1), float3(0.68, 0.76, 0.82), clearPlastic);
        if (carouselPrismatic && clearPlastic > 0.001) {
            float2 split = n * (0.6 + min(0.9, bleed.height * 0.025)) * (1 - t) * (1 - t) * clearPlastic;
            float2 inCard = float2(dot(split, k.rotation), -split.x * k.rotation.y + split.y * k.rotation.x) * point.footprint;
            float3 red = frontField ? carouselNeighbourFrontFieldColour(point.local - inCard, lod, k, source, images[i], sampling, stock) :
                carouselNeighbourColour(point.local - inCard, lod, sourcePixel, source, images[i], videos[i], sampling, stock);
            float3 blue = frontField ? carouselNeighbourFrontFieldColour(point.local + inCard, lod, k, source, images[i], sampling, stock) :
                carouselNeighbourColour(point.local + inCard, lod, sourcePixel, source, images[i], videos[i], sampling, stock);
            seen = float3(red.r, seen.g, blue.b);
        }
        premultiplied = premultiplied * (1 - cover) + seen * cover;
        alpha = alpha * (1 - cover) + cover;
    }
    float band = 1 - t;
    return float4(premultiplied / max(alpha, 1e-4), alpha * bleed.strength * band * band);
}

// Card space to the screen's frame: the turn about the vertical axis, then the tilt.
static float3 carouselSlabToWorld(float3 v, float cosine, float sine, float2 rotation) {
    float3 turned = float3(v.x * cosine + v.z * sine, v.y, -v.x * sine + v.z * cosine);
    return float3(turned.x * rotation.x - turned.y * rotation.y, turned.x * rotation.y + turned.y * rotation.x, turned.z);
}

struct CarouselSceneRay {
    float3 origin;
    float3 direction;
    float3 originDx;
    float3 originDy;
    float3 directionDx;
    float3 directionDy;
    float3 basisX;
    float3 basisY;
    float baseRadius;
    float aperture;
    float range;
};

static float3 carouselSceneNormal(float3 normal, constant CarouselSceneUniforms &scene) {
    float3x3 inverse = float3x3(scene.sceneToReceiver[0].xyz, scene.sceneToReceiver[1].xyz,
                                scene.sceneToReceiver[2].xyz);
    return normalize(transpose(inverse) * normal);
}

// Source derivatives are the analytic ray/plane Jacobian. They are evaluated
// before silhouette rejection, so steep turned faces select finite filtered mips.
static float3 carouselSceneColour(float2 q, float2 qDx, float2 qDy, float along,
                                   constant CarouselSceneSource &source,
                                   texture2d<float> image, texture2d<float> videoImage,
                                   sampler sampling, float3 stock, float roughness,
                                   constant CarouselCardColorUniforms &cardColor, bool coatSource,
                                   bool laminateDiffusion) {
    float2 coatPoint = q;
    if (laminateDiffusion) {
        float2 printHalf = source.uvScale.x < 0 ? source.paperHalf : source.imageHalf;
        float radius = source.uvScale.x < 0 ? source.paperRadius : source.imageRadius;
        float edge = roundedDistance(q, printHalf, radius);
        if (edge > 0) q -= edge * carouselRoundedNormal(q, printHalf, radius);
    }
    float2 uv = q * source.uvScale + 0.5;
    float2 dx = qDx * source.uvScale, dy = qDy * source.uvScale;
    float2 dimensions = float2(image.get_width(), image.get_height());
    float rho = max(length(dx * dimensions), length(dy * dimensions));
    float lod = log2(max(rho, 1.0));
    float4 picture = image.sample(sampling, uv, level(lod));
    if (carouselPrismatic) {
        // Separate spatial colour detail without adding energy to neutral UI.
        float2 split = dx * 0.7;
        float4 red = image.sample(sampling, uv - split, level(lod));
        float4 blue = image.sample(sampling, uv + split, level(lod));
        picture.rgb = float3(red.r / max(red.a, 1e-4), picture.g / max(picture.a, 1e-4),
                              blue.b / max(blue.a, 1e-4)) * picture.a;
    }
    float3 colour;
    if (source.uvScale.x < 0) {
        if (source.video.backSize.x > 0) {
            float2 inBack = uv * source.video.backSize - source.video.panelCenter;
            float panelAA = max(0.6, max(length(dx * source.video.backSize), length(dy * source.video.backSize)));
            float mask = 1 - smoothstep(-panelAA * 0.5, panelAA * 0.5,
                roundedDistance(inBack, source.video.panelHalf, source.video.radius));
            if (mask != 0) {
                float2 fitScale = source.video.fit / max(2 * source.video.panelHalf, float2(1));
                float2 seen = inBack * fitScale + 0.5;
                float2 videoDx = dx * source.video.backSize * fitScale;
                float2 videoDy = dy * source.video.backSize * fitScale;
                // Explicit gradients keep all five filtering taps unchanged while
                // pixels wholly outside this panel need no video texture fetches.
                float2 spreadX = videoDx * 0.7, spreadY = videoDy * 0.7;
                float3 videoColour = 0.4 * videoImage.sample(sampling, seen, gradient2d(videoDx, videoDy)).rgb +
                    0.15 * (videoImage.sample(sampling, seen + spreadX, gradient2d(videoDx, videoDy)).rgb +
                            videoImage.sample(sampling, seen - spreadX, gradient2d(videoDx, videoDy)).rgb +
                            videoImage.sample(sampling, seen + spreadY, gradient2d(videoDx, videoDy)).rgb +
                            videoImage.sample(sampling, seen - spreadY, gradient2d(videoDx, videoDy)).rgb);
                picture = mix(picture, float4(videoColour, 1), mask);
            }
        }
        colour = picture.rgb + stock * (1 - picture.a);
    } else if (laminateDiffusion) {
        // The printed colour diffuses through its own clear coating. Geometry
        // already supplies that coating's coverage; masking the print a second
        // time here would dilute every filtered edge sample with paper stock.
        colour = picture.rgb + stock * (1 - picture.a);
    } else {
        float aa = max(0.35, max(length(qDx), length(qDy)));
        float cover = 1 - smoothstep(-aa * 0.5, aa * 0.5,
            roundedDistance(q, source.imageHalf, source.imageRadius));
        colour = picture.rgb * cover + stock * (1 - picture.a * cover);
    }
    if (carouselColorsCard && coatSource) {
        float3 noTransmission = 0;
        carouselApplyCardColor(coatPoint, source.paperHalf + source.margin, cardColor, colour, noTransmission);
    }
    return colour * source.tint;
}

// Primary paper visibility uses the same global ray and rigid source planes as
// optics. Transparent plastic does not hide another print; nearer paper does.
static float carouselScenePrimaryVisibility(float2 screen, float3 localPoint,
                                             constant CarouselSceneUniforms &scene) {
    float3 point = (scene.receiverToScene * float4(localPoint, 1)).xyz;
    float ownDistance = length(point - scene.eye.xyz);
    float3 direction = normalize(float3(screen - scene.eye.xy, -scene.eye.z));
    float3 dx = dfdx(direction), dy = dfdy(direction);
    float visible = 1;
    uint receiverSlot = 0;
    for (uint i = 0; i < min(scene.count, 8u); i++) {
        if (scene.sources[i].index == scene.receiverIndex) receiverSlot = i;
    }
    for (uint i = 0; i < min(scene.count, 8u); i++) {
        constant CarouselSceneSource &source = scene.sources[i];
        if (source.index == scene.receiverIndex) continue;
        float3 o = (source.sceneToSlab * float4(scene.eye.xyz, 1)).xyz;
        float3 d = (source.sceneToSlab * float4(direction, 0)).xyz;
        if (!(abs(d.z) > 1e-6)) continue;
        float divisor = abs(d.z) > 1e-6 ? d.z : (d.z < 0 ? -1e-6 : 1e-6);
        float along = clamp((source.depth - o.z) / divisor, -1e6, 1e6);
        bool nearer = along < ownDistance - 0.01 || (abs(along - ownDistance) <= 0.01 && i > receiverSlot);
        if (!(along > 0 && nearer)) continue;
        float2 q = o.xy + d.xy * along;
        if (!all(isfinite(q))) continue;
        float3 ddx = (source.sceneToSlab * float4(dx, 0)).xyz;
        float3 ddy = (source.sceneToSlab * float4(dy, 0)).xyz;
        float2 qDx = along * (ddx.xy - d.xy * ddx.z / divisor);
        float2 qDy = along * (ddy.xy - d.xy * ddy.z / divisor);
        float aa = max(0.35, max(length(qDx), length(qDy)));
        if (!(aa < 1e4)) continue;
        float cover = (1 - smoothstep(-aa * 0.5, aa * 0.5,
            roundedDistance(q, source.paperHalf, source.paperRadius))) * source.opacity;
        visible *= 1 - cover;
        // Derivatives were evaluated before the loop. Once opaque paper fully
        // hides this fragment, later sources cannot change its visibility.
        if (carouselSkipHiddenShading && visible == 0) break;
    }
    return visible;
}

// Actual positive ray hits, ordered by world distance rather than screen draw
// order. Opaque paper blocks farther sources; a fading card transmits the rest.
// The source's visible UI radiance is deliberately double-sided. Its real plane,
// rounded bounds, elevation and nearer paper still determine every optical hit.
static float4 carouselSceneTrace(CarouselSceneRay ray, constant CarouselSceneUniforms &scene,
                                  array<texture2d<float>, 8> images,
                                  array<texture2d<float>, 8> videos, sampler sampling,
                                  float3 stock, bool foregroundOnly,
                                  constant CarouselCardColorUniforms &cardColor) {
    // Keep only ordering data live across the source scan. The selected source's
    // footprint and colour are evaluated together, rather than retained in arrays.
    float distances[8];
    uint count = min(scene.count, 8u);
    for (uint i = 0; i < count; i++) {
        distances[i] = 1e9;
        constant CarouselSceneSource &source = scene.sources[i];
        if (source.index == scene.receiverIndex) continue;
        float3 origin = (source.sceneToSlab * float4(ray.origin, 1)).xyz;
        float3 direction = (source.sceneToSlab * float4(ray.direction, 0)).xyz;
        if (!(abs(direction.z) > 1e-6)) continue;
        float divisor = abs(direction.z) > 1e-6 ? direction.z : (direction.z < 0 ? -1e-6 : 1e-6);
        float along = clamp((source.depth - origin.z) / divisor, -1e6, 1e6);
        // These sources had zero coverage or a zero range taper already. Reject
        // them before the analytic Jacobian, cone projection and Gaussian work.
        if (!(along > 0.005 && along < 1e6) || (ray.range > 0 && along >= ray.range)) continue;
        float2 q = origin.xy + direction.xy * along;
        if (!all(isfinite(q))) continue;
        distances[i] = along;
    }
    float3 radiance = 0;
    float emittedCoverage = 0, remaining = 1;
    for (uint step = 0; step < count && remaining > 0.0001; step++) {
        float nearest = 1e9;
        uint slot = count;
        for (uint i = 0; i < count; i++) {
            if (distances[i] < nearest) { nearest = distances[i]; slot = i; }
        }
        if (slot == count) break;
        distances[slot] = 1e9;
        constant CarouselSceneSource &source = scene.sources[slot];
        float3 origin = (source.sceneToSlab * float4(ray.origin, 1)).xyz;
        float3 direction = (source.sceneToSlab * float4(ray.direction, 0)).xyz;
        float divisor = abs(direction.z) > 1e-6 ? direction.z : (direction.z < 0 ? -1e-6 : 1e-6);
        float along = nearest;
        float2 q = origin.xy + direction.xy * along;
        float3 originDx = (source.sceneToSlab * float4(ray.originDx, 0)).xyz;
        float3 originDy = (source.sceneToSlab * float4(ray.originDy, 0)).xyz;
        float3 directionDx = (source.sceneToSlab * float4(ray.directionDx, 0)).xyz;
        float3 directionDy = (source.sceneToSlab * float4(ray.directionDy, 0)).xyz;
        float2 qDx = originDx.xy + directionDx.xy * along +
            direction.xy * (-originDx.z - along * directionDx.z) / divisor;
        float2 qDy = originDy.xy + directionDy.xy * along +
            direction.xy * (-originDy.z - along * directionDy.z) / divisor;
        // Convert the world cone disk through the complete ray/plane Jacobian.
        // Local texel density alone cannot describe a tilted or sheared source.
        float radius = ray.baseRadius + max(0.0, along) * ray.aperture;
        float3 bx = (source.sceneToSlab * float4(ray.basisX * radius, 0)).xyz;
        float3 by = (source.sceneToSlab * float4(ray.basisY * radius, 0)).xyz;
        float2 coneDx = bx.xy - direction.xy * bx.z / divisor;
        float2 coneDy = by.xy - direction.xy * by.z / divisor;
        if (dot(coneDx, coneDx) > dot(qDx, qDx)) qDx = coneDx;
        if (dot(coneDy, coneDy) > dot(qDy, qDy)) qDy = coneDy;
        float footprint = max(0.35, max(length(qDx), length(qDy)));
        if (!(footprint < 1e4)) continue;
        float taper = ray.range > 0 ? 1 - smoothstep(ray.range / 3, ray.range, max(0.0, along)) : 1;
        float edge = roundedDistance(q, source.paperHalf, source.paperRadius);
        float sigma = max(footprint * 0.60, 0.175);
        float z = clamp(edge / sigma, -8.0, 8.0);
        float gaussianCover = (1 / (1 + exp(1.702 * z))) * (1 - smoothstep(3.5, 4.5, z));
        float cover = gaussianCover * source.opacity;
        float emittedCover = cover;
        if (!foregroundOnly) {
            // Broad scattering originates on the real laminated surface, whose
            // clear margin carries filtered colour from its own paper. Only
            // paper coverage below blocks another surface along the beam.
            float outerEdge = roundedDistance(q, source.paperHalf + source.margin, source.outerRadius);
            float outerZ = clamp(outerEdge / sigma, -8.0, 8.0);
            float coating = (1 / (1 + exp(1.702 * outerZ))) * (1 - smoothstep(3.5, 4.5, outerZ));
            emittedCover = coating * source.opacity;
        }
        // Preserve the old source admission rule: a rejected filtered footprint
        // or negligible emission neither samples nor blocks farther sources.
        if (!(emittedCover > 0.0001 && taper > 0)) continue;
        float emission = source.radiance.x;
        if (foregroundOnly && source.radiance.y <= 0) emission = 0;
        if (emission > 0) {
            float weight = min(1 - emittedCoverage,
                remaining * emittedCover * emission * taper);
            if (weight != 0) {
                float3 colour = carouselSceneColour(q, qDx, qDy, nearest,
                    source, images[slot], videos[slot], sampling, stock, 0, cardColor, true,
                    !foregroundOnly);
                radiance += weight * colour;
            }
            emittedCoverage += weight;
        }
        remaining *= 1 - cover;
    }
    return float4(radiance, emittedCoverage);
}

// The established circular edge profile now shifts a virtual optical pupil in
// card space. Finite ray bundles leave that pupil in both plane-normal directions;
// their real world intersections, depth taper and growing footprints determine
// every colour. No source is picked because of screen proximity or promotion.
static float4 carouselSceneBleed(float3 localPoint, CarouselSlabShape shape, float edgeDistance, float coverage,
                                  constant CarouselBleedUniforms &bleed,
                                  constant CarouselSceneUniforms &scene,
                                  constant CarouselSlabUniforms &slab,
                                  array<texture2d<float>, 8> images,
                                  array<texture2d<float>, 8> videos, sampler sampling,
                                  constant CarouselCardColorUniforms &cardColor) {
    float t = saturate(-edgeDistance / max(bleed.height, 1.0));
    float band = 1 - t;
    if (scene.count == 0 || bleed.strength <= 0) return 0;
    float2 rim = carouselRoundedNormal(localPoint.xy, shape.halfSize, shape.radius);
    if (dot(rim, rim) < 1e-8) rim = float2(1, 0);
    float shift = bleed.height * (1 - sqrt(t * (2 - t)));
    float3 pupil = (scene.receiverToScene * float4(localPoint + float3(rim * shift, 0), 1)).xyz;
    float3 normal = carouselSceneNormal(float3(0, 0, 1), scene);
    float3 x = normalize((scene.receiverToScene * float4(rim, 0, 0)).xyz);
    float3 y = normalize(cross(normal, x));
    float radius = length((scene.receiverToScene * float4(rim * bleed.blur, 0, 0)).xyz);
    float roughness = carouselMaterialRoughness(slab.roughness);
    float aperture = 0.12 + 0.45 * roughness * roughness;
    if (carouselFrosted) aperture = max(aperture, 0.24);
    float3 pupilDx = dfdx(pupil), pupilDy = dfdy(pupil);
    float3 normalDx = dfdx(normal), normalDy = dfdy(normal);
    // The analytic cone footprint integrates blur and rounded source coverage.
    // Its pixel derivatives precede all varying rejection; spreading additional
    // pupil samples would filter that same footprint a second time.
    if (band <= 0 || coverage <= 0) return 0;
    float4 hemispheres[2] = {float4(0), float4(0)};
    for (uint side = 0; side < 2; side++) {
        float sign = side == 0 ? 1.0 : -1.0;
        CarouselSceneRay ray;
        ray.origin = pupil;
        ray.direction = normal * sign;
        ray.originDx = pupilDx; ray.originDy = pupilDy;
        ray.directionDx = normalDx * sign; ray.directionDy = normalDy * sign;
        ray.basisX = x; ray.basisY = y;
        ray.baseRadius = radius * 0.80;
        ray.aperture = aperture;
        ray.range = max(scene.beam.x, 1.0);
        hemispheres[side] = carouselSceneTrace(ray, scene, images, videos, sampling, slab.stock.rgb,
                                              false, cardColor);
    }
    float sum = hemispheres[0].a + hemispheres[1].a;
    float beamCoverage = sum - hemispheres[0].a * hemispheres[1].a;
    float3 colour = (hemispheres[0].rgb + hemispheres[1].rgb) / max(sum, 1e-4);
    return float4(colour, beamCoverage * bleed.strength * band * band);
}

// The optional glossy lobe uses the same world camera, source planes and source
// visibility as broad edge bleed, with a true studio-direction reflection ray.
static void carouselSceneReflection(float3 localPoint, float3 localNormal, CarouselSlabShape shape,
                                 float clearPlastic, float coverage, float3 residualStudio,
                                 constant CarouselSceneUniforms &scene,
                                 constant CarouselSlabUniforms &slab,
                                 array<texture2d<float>, 8> images,
                                 array<texture2d<float>, 8> videos, sampler sampling,
                                 constant CarouselCardColorUniforms &cardColor,
                                 thread float3 &light) {
    if (scene.count == 0 || scene.eye.w <= 0 || slab.highlight <= 0) return;
    float3 point = (scene.receiverToScene * float4(localPoint, 1)).xyz;
    float3 normal = carouselSceneNormal(localNormal, scene);
    float3 incident = normalize(point - scene.eye.xyz);
    if (dot(incident, normal) > 0) normal = -normal;
    float nov = max(-dot(incident, normal), 1e-3);
    float3 reflected = reflect(incident, normal);
    CarouselSceneRay reflection;
    reflection.origin = point + reflected * 0.01;
    reflection.direction = reflected;
    reflection.originDx = dfdx(reflection.origin); reflection.originDy = dfdy(reflection.origin);
    reflection.directionDx = dfdx(reflected); reflection.directionDy = dfdy(reflected);
    reflection.basisX = normalize(cross(reflected, abs(reflected.z) < 0.9 ? float3(0, 0, 1) : float3(0, 1, 0)));
    reflection.basisY = normalize(cross(reflected, reflection.basisX));
    reflection.baseRadius = 0; reflection.range = 0;
    float3 normalDx = dfdx(normal), normalDy = dfdy(normal);
    float roughness = carouselFilteredRoughness(carouselMaterialRoughness(slab.roughness),
        dot(normalDx, normalDx) + dot(normalDy, normalDy));
    reflection.aperture = roughness * roughness * 0.10;
    // Differentials precede varying rejection. Opaque artwork stays unchanged.
    if (coverage <= 0 || clearPlastic <= 0.001) return;
    float4 hit = carouselSceneTrace(reflection, scene, images, videos, sampling, slab.stock.rgb,
        true, cardColor);
    float strength = saturate(scene.eye.w * clearPlastic);
    float weight = strength * slab.highlight * carouselFresnel(nov, 1 / shape.ior);
    // Replace the covered residual studio radiance rather than add another
    // reflection lobe. Non-emitting wheel blockers leave the baseline untouched.
    light += hit.rgb * weight - residualStudio * strength * hit.a;
}

fragment CarouselSlabOutput carouselSlabFragment(CarouselSlabVertex input [[stage_in]],
                                                 constant CarouselCardUniforms &u [[buffer(0)]],
                                                 constant CarouselOccluderUniforms *occluders
                                                     [[buffer(1), function_constant(carouselLegacyOcclusion)]],
                                                 constant CarouselSlabUniforms &slab [[buffer(2)]],
                                                 texture2d<float> image [[texture(0)]],
                                                 sampler sampling [[sampler(0)]],
                                                 texturecube<float> studio [[texture(1)]],
                                                 texturecube<float> irradiance [[texture(2)]],
                                                 texture2d<float> backImage [[texture(3)]],
                                                 constant CarouselBleedUniforms &bleed [[buffer(3)]],
                                                 array<texture2d<float>, 4> neighbourImages
                                                     [[texture(4), function_constant(carouselLegacySources)]],
                                                 constant CarouselBackVideoUniforms &video [[buffer(4)]],
                                                 texture2d<float> videoImage [[texture(8)]],
                                                 constant CarouselRefractionUniforms &refraction
                                                     [[buffer(6), function_constant(carouselRefinedSources)]],
                                                 array<texture2d<float>, 4> neighbourVideos
                                                     [[texture(9), function_constant(carouselRefinedSources)]],
                                                 constant CarouselSceneUniforms &scene
                                                     [[buffer(7), function_constant(carouselSceneDepth)]],
                                                 array<texture2d<float>, 8> sceneImages
                                                     [[texture(13), function_constant(carouselSceneDepth)]],
                                                 array<texture2d<float>, 8> sceneVideos
                                                     [[texture(21), function_constant(carouselSceneDepth)]],
                                                 constant CarouselCardColorUniforms &cardColor
                                                     [[buffer(5), function_constant(carouselColorsCard)]]) {
    constexpr sampler environment(filter::linear, mip_filter::linear);
    float2 p = input.screen;
    CarouselSlabShape s = carouselSlabShape(u, slab);
    float3 stock = slab.stock.rgb;
    float f0 = (s.ior - 1) / (s.ior + 1);
    f0 *= f0;
    float pixel = max(max(fwidth(p.x), fwidth(p.y)), 0.35);
    float2 screen = u.center + float2(p.x * u.rotation.x - p.y * u.rotation.y,
                                      p.x * u.rotation.y + p.y * u.rotation.x);
    float coverage;
    float3 light = 0;        // toward the eye
    float3 through = 0;      // the share of the drawable behind that shows through
    float2 facePoint;        // where the pixel's ray meets the face's plane: the shadow's plane
    float bleedDistance = 0;  // from the outline (negative inside) and its outward normal, for the bleed
    float2 bleedNormal = 0;
    float materialNov = 1;
    float clearPlastic = 0;
    float2 colorPoint = p;
    float3 opticalPoint = float3(p, 0);
    float3 opticalNormal = float3(0, 0, 1);
    float3 visibilityPoint = float3(p, 0);
    float sceneVisibility = 1;
    float3 surfaceReflection = 0;
    if (!carouselSceneDepth && (!carouselPromoted || u.turn == 0)) {
        // A flat card: the eye ray through `p` meets the face at `p`. Only the rounded
        // edge's band needs the slab: going down, the ray drifts outward by p / distance
        // per point of depth until it meets the bevel, or passes it.
        float r = s.bevel;
        float outer = roundedDistance(p, s.halfSize, s.radius);
        float outerAA = max(fwidth(outer), 0.35);
        float3 n = float3(0, 0, 1);
        float depth = 0;
        float silhouette = outer;
        bool band = r > 1e-4 && outer > -r;
        if (band) {
            float2 outward = carouselRoundedNormal(p, s.halfSize, s.radius);
            // In bevel radii: the ray starts xi0 out from the bevel's inner edge, on the
            // face, and drifts a outward per radius of depth.
            float a = max(dot(outward, p), 0.0) / s.distance;
            float xi0 = (r + outer) / r;
            float e = s.exponent;
            float q = e / (e - 1.0);
            // The ray grazing the bevel starts here: the silhouette on screen.
            float grazing = powr(1.0 + powr(a, q), 1.0 / q) - a;
            silhouette = outer + r * (1.0 - grazing);
            // A miss shades the ray's closest approach, for the silhouette's antialiasing.
            float tau = clamp((1.0 - a * xi0) / (1.0 + a * a), 0.0, 1.0);
            if (e < 2.001) {
                float disc = 1.0 - 2.0 * a * xi0 - xi0 * xi0;
                if (disc >= 0.0) tau = ((1.0 - a * xi0) - sqrt(disc)) / (1.0 + a * a);
            } else {
                // The profile is convex along the ray, so Newton steps never pass its hit.
                float t = 0.0;
                #pragma clang loop unroll(disable)
                for (int i = 0; i < 8; i++) {
                    float x = max(xi0 + a * t, 0.0), y = max(1.0 - t, 0.0);
                    float g = powr(x, e) + powr(y, e) - 1.0;
                    float slope = e * a * powr(x, e - 1.0) - e * powr(y, e - 1.0);
                    if (g <= 1e-5 || slope >= -1e-6) break;
                    t -= g / slope;
                }
                float x = max(xi0 + a * t, 0.0), y = max(1.0 - t, 0.0);
                if (powr(x, e) + powr(y, e) - 1.0 <= 1e-3) tau = t;
            }
            float x = saturate(xi0 + a * tau), y = saturate(1.0 - tau);
            n = normalize(float3(outward * powr(x, e - 1.0), powr(y, e - 1.0)));
            depth = r * tau;
        }
        float3 worldNormal = float3(n.x * u.rotation.x - n.y * u.rotation.y,
                                    n.x * u.rotation.y + n.y * u.rotation.x, n.z);
        float3 worldView = normalize(slab.eye.xyz - float3(screen, -depth));
        if (carouselSceneDepth) {
            float3 point = (scene.receiverToScene * float4(p * (1 + depth / s.distance), -depth, 1)).xyz;
            worldNormal = carouselSceneNormal(n, scene);
            worldView = normalize(scene.eye.xyz - point);
        }
        float3 dnx = dfdx(worldNormal), dny = dfdy(worldNormal);
        float roughness = carouselFilteredRoughness(carouselMaterialRoughness(slab.roughness),
                                                     dot(dnx, dnx) + dot(dny, dny));
        // The paper, inside the clear margin, and the image printed on it.
        float paper = roundedDistance(p, s.paperHalf, s.paperRadius);
        float paperAA = max(fwidth(paper), 0.35);
        float onPaper = 1 - smoothstep(-paperAA * 0.5, paperAA * 0.5, paper);
        clearPlastic = 1 - onPaper;
        float distance = roundedDistance(p, u.imageHalf, u.imageRadius);
        float aa = max(fwidth(distance), 0.35);
        float imageCoverage = 1 - smoothstep(-aa * 0.5, aa * 0.5, distance);
        float4 print = image.sample(sampling, p * u.uvScale + 0.5);
        float edge = 1 - smoothstep(0.0, u.edgeWidth, max(0.0, -distance));
        print.rgb = min(float3(print.a), print.rgb + 0.07 * edge * print.a);
        float3 albedo = print.rgb * imageCoverage + stock * (1 - print.a * imageCoverage);
        if (carouselPaperShading) {
            float2 paperRim = carouselRoundedNormal(p, s.paperHalf, s.paperRadius);
            float2 worldRim = float2(paperRim.x * u.rotation.x - paperRim.y * u.rotation.y,
                                      paperRim.x * u.rotation.y + paperRim.y * u.rotation.x);
            albedo *= carouselPaperLight(float3(0, 0, 1), screen - u.center,
                                          2 * s.halfSize.x, 1, paper, worldRim, paperAA);
        }
        // The surface's gloss, then what passes into the plastic: the print, kept as it is
        // when the card faces the screen, or, in the margin and the edge, what is behind.
        float nov = max(dot(worldNormal, worldView), 1e-3);
        materialNov = nov;
        float3 mirrored = reflect(-worldView, worldNormal);
        float3 reflectedStudio = studio.sample(environment, mirrored, level(roughness * slab.maxLod)).rgb;
        if (carouselRefinedReflections) {
            light = carouselRefinedReflection(reflectedStudio + carouselRefinedGloss(mirrored, roughness, slab),
                                               roughness, nov, f0, slab);
        } else {
            float2 ab = carouselEnvironmentBRDF(roughness, nov);
            light = slab.highlight * (f0 * ab.x + ab.y) *
                (reflectedStudio + carouselGlossLights(mirrored, roughness, slab));
        }
        light = carouselMaterialReflection(light, nov, worldNormal);
        surfaceReflection = light;
        opticalPoint = float3(p * (1 + depth / s.distance), -depth);
        opticalNormal = n;
        float entering = 1 - carouselFresnel(nov, 1 / s.ior);
        float3 inside = refract(-worldView, worldNormal, 1 / s.ior);
        float cosine = max(-inside.z, 1e-3);
        float leaving = 1 - carouselFresnel(cosine, s.ior);
        float3 absorbed = exp(-s.sigma * min((s.thickness - depth) / cosine, 3 * s.thickness));
        float3 trapped = studio.sample(environment, reflect(inside, float3(0, 0, -1)), level(slab.maxLod)).rgb;
        if (carouselRefinedReflections) {
            light += onPaper * albedo * entering +
                (1 - onPaper) * entering * (1 - leaving) * absorbed * trapped;
        } else {
            light += onPaper * albedo * entering / (1 - f0) +
                (1 - onPaper) * entering * (1 - leaving) * absorbed * trapped;
        }
        through = (1 - onPaper) * entering * leaving * absorbed;
        coverage = 1 - smoothstep(-outerAA * 0.5, outerAA * 0.5, silhouette);
        facePoint = p;
        float2 rim = carouselRoundedNormal(p, s.halfSize, s.radius);
        bleedDistance = outer;
        bleedNormal = float2(rim.x * u.rotation.x - rim.y * u.rotation.y, rim.x * u.rotation.y + rim.y * u.rotation.x);
    } else {
        // A turning card: the eye ray through `p`, cast in card space.
        float c = cos(u.turn), sn = sin(u.turn);
        float d = s.distance, t = s.thickness, r = s.bevel;
        float3 eye = float3(-d * sn, 0, d * c);
        float3 ray = normalize(float3(p.x * c + d * sn, p.y, p.x * sn - d * c));
        if (carouselSceneDepth) {
            eye = (scene.sceneToReceiver * float4(scene.eye.xyz, 1)).xyz;
            float3 worldRay = normalize(float3(screen - scene.eye.xy, -scene.eye.z));
            ray = normalize((scene.sceneToReceiver * float4(worldRay, 0)).xyz);
        }
        float toPlane = abs(ray.z) > 1e-6 ? -eye.z / ray.z : -1.0;
        facePoint = toPlane > 0 ? (eye + ray * toPlane).xy : float2(1e5);
        visibilityPoint = toPlane > 0 ? eye + ray * toPlane : eye;
        bool hit = false, onFace = false, onBack = false, beside = false;
        float3 point = eye;
        if (eye.z > 0 && ray.z < -1e-6) {
            point = eye + ray * (-eye.z / ray.z);
            onFace = hit = -roundedDistance(point.xy, s.halfSize, s.radius) >= r;
        }
        if (!hit && eye.z < -t && ray.z > 1e-6) {
            point = eye + ray * ((-t - eye.z) / ray.z);
            onBack = hit = -roundedDistance(point.xy, s.halfSize, s.radius) >= r;
        }
        float closest = -1e3;   // how far the ray passes outside the slab (negative: through it)
        float3 n = onBack ? float3(0, 0, -1) : float3(0, 0, 1);
        if (!hit) {
            float2 box = carouselSlabBox(eye, ray, s);
            beside = box.x > box.y;
            if (!beside) {
                float along = box.x, before = box.x;
                hit = carouselSlabHit(eye, ray, box.y, along, before, s);
                point = eye + ray * along;
                n = carouselSlabNormal(point, s);
                // Near the silhouette, the ray's closest approach antialiases it; a miss is
                // shaded there.
                if (!hit || dot(n, -ray) < 0.75) {
                    float at = along;
                    closest = carouselSlabClosest(eye, ray, hit ? along : before, hit ? box.y : along, at, s);
                    if (!hit) {
                        point = eye + ray * at;
                        n = carouselSlabNormal(point, s);
                    }
                }
            }
        }
        colorPoint = point.xy;
        opticalPoint = point;
        opticalNormal = n;
        if (hit) visibilityPoint = point;
        float depthAlong = max(dot(point - eye, float3(sn, 0, -c)), 1.0);
        coverage = beside ? 0 : 1 - smoothstep(-pixel * 0.5, pixel * 0.5, closest * d / depthAlong);
        if (carouselSceneDepth) {
            float3 worldPoint = (scene.receiverToScene * float4(point, 1)).xyz;
            float scale = length(scene.receiverToScene[0].xyz);
            float projectedDistance = closest * scale * scene.eye.z / max(length(worldPoint - scene.eye.xyz), 1.0);
            coverage = beside ? 0 : 1 - smoothstep(-pixel * 0.5, pixel * 0.5, projectedDistance);
        }
        // Shadow-only fragments do not enter the plastic. Keep the original
        // coverage guard around paper intersection, which has no derivatives.
        float3 inside = 0;
        CarouselPaperHit sheet = {-1, 0};
        if (coverage > 0) {
            inside = refract(ray, n, 1 / s.ior);
            sheet = carouselPaperHit(point, inside, s);
            if (sheet.along >= 0) visibilityPoint = point + inside * sheet.along;
        }
        if (carouselSceneDepth && carouselSkipHiddenShading) {
            sceneVisibility = carouselScenePrimaryVisibility(screen, visibilityPoint, scene);
        }
        // Derivatives below still run in every lane. Compute their temporary
        // values after the visibility loop to avoid retaining them across it.
        float3 worldNormal = carouselSlabToWorld(n, c, sn, u.rotation);
        float3 localRim = float3(carouselRoundedNormal(point.xy, s.halfSize, s.radius), 0);
        float2 rim = carouselSlabToWorld(localRim, c, sn, u.rotation).xy;
        if (carouselSceneDepth) rim = (scene.receiverToScene * float4(localRim, 0)).xy;
        bleedDistance = roundedDistance(point.xy, s.halfSize, s.radius);
        bleedNormal = rim / max(length(rim), 1e-4);
        float3 world = float3(screen, -point.x * sn + point.z * c);
        float3 worldView = normalize(slab.eye.xyz - world);
        if (carouselSceneDepth) {
            world = (scene.receiverToScene * float4(point, 1)).xyz;
            worldNormal = carouselSceneNormal(n, scene);
            worldView = normalize(scene.eye.xyz - world);
        }
        float3 dnx = dfdx(worldNormal), dny = dfdy(worldNormal);
        float roughness = carouselFilteredRoughness(carouselMaterialRoughness(slab.roughness),
                                                     dot(dnx, dnx) + dot(dny, dny));
        // The print's mip level follows the face's plane, smooth across the silhouette; the
        // back's, the paper's back plane. Seen from behind, the back's picture reads the
        // right way round: it is mirrored across the card.
        float2 faceUV = facePoint * u.uvScale;
        float2 faceDx = dfdx(faceUV), faceDy = dfdy(faceUV);
        float toBack = abs(ray.z) > 1e-6 ? (s.paperBottom - eye.z) / ray.z : -1.0;
        float2 backPoint = toBack > 0 ? (eye + ray * toBack).xy : float2(1e5);
        float2 backScale = float2(-0.5, 0.5) / max(s.paperHalf, float2(1.0));
        float2 backUV = backPoint * backScale;
        float2 backDx = dfdx(backUV), backDy = dfdy(backUV);
        // Fully covered paper needs no material samples. Partial visibility keeps
        // the complete material and optical calculation, including antialiasing.
        if (coverage > 0 && sceneVisibility > 0) {
            float nov = max(dot(worldNormal, worldView), 1e-3);
            materialNov = nov;
            float3 mirrored = reflect(-worldView, worldNormal);
            float3 reflectedStudio = studio.sample(environment, mirrored, level(roughness * slab.maxLod)).rgb;
            if (carouselRefinedReflections) {
                light = carouselRefinedReflection(reflectedStudio + carouselRefinedGloss(mirrored, roughness, slab),
                                                   roughness, nov, f0, slab);
            } else {
                float2 ab = carouselEnvironmentBRDF(roughness, nov);
                light = slab.highlight * (f0 * ab.x + ab.y) *
                    (reflectedStudio + carouselGlossLights(mirrored, roughness, slab));
            }
            light = carouselMaterialReflection(light, nov, worldNormal);
            surfaceReflection = light;
            float entering = 1 - carouselFresnel(nov, 1 / s.ior);
            // Refracted into the plastic, the ray meets the paper or crosses to the far face.
            if (sheet.along >= 0) {
                float3 q = point + inside * sheet.along;
                visibilityPoint = q;
                float3 albedo = stock;
                float3 facing = float3(0, 0, -1);
                if (sheet.face == 1) {
                    float4 print = image.sample(sampling, q.xy * u.uvScale + 0.5, gradient2d(faceDx, faceDy));
                    float distance = roundedDistance(q.xy, u.imageHalf, u.imageRadius);
                    float imageCoverage = 1 - smoothstep(-0.25, 0.25, distance);
                    float edge = 1 - smoothstep(0.0, u.edgeWidth, max(0.0, -distance));
                    print.rgb = min(float3(print.a), print.rgb + 0.07 * edge * print.a);
                    albedo = print.rgb * imageCoverage + stock * (1 - print.a * imageCoverage);
                    facing = float3(0, 0, 1);
                } else if (sheet.face == -1) {
                    float2 backUV = q.xy * backScale + 0.5;
                    float4 picture = backImage.sample(sampling, backUV, gradient2d(backDx, backDy));
                    // The back video plays in its panel, printed with the rest of the back.
                    if (video.backSize.x > 0) {
                        float2 inBack = backUV * video.backSize - video.panelCenter;
                        float inside = 1 - smoothstep(-0.6, 0.6, roundedDistance(inBack, video.panelHalf, video.radius));
                        if (inside > 0) {
                            float2 seen = inBack / max(2 * video.panelHalf, float2(1)) * video.fit + 0.5;
                            float3 videoColour;
                            videoColour = videoImage.sample(sampling, seen, level(0)).rgb;
                            picture = mix(picture, float4(videoColour, 1), inside);
                        }
                    }
                    albedo = picture.rgb + stock * (1 - picture.a);
                } else {
                    facing = float3(carouselOutline(q.xy, s.paperHalf, s.paperRadius).normal, 0);
                }
                float3 paperNormal = carouselSlabToWorld(facing, c, sn, u.rotation);
                if (carouselSceneDepth) paperNormal = carouselSceneNormal(facing, scene);
                float k = irradiance.sample(environment, paperNormal, level(0)).r;
                if (carouselPaperShading) {
                    float paperDistance = roundedDistance(q.xy, s.paperHalf, s.paperRadius);
                    float2 paperRim = carouselSlabToWorld(float3(carouselRoundedNormal(q.xy, s.paperHalf, s.paperRadius), 0),
                                                         c, sn, u.rotation).xy;
                    if (carouselSceneDepth) paperRim = (scene.receiverToScene * float4(
                        carouselRoundedNormal(q.xy, s.paperHalf, s.paperRadius), 0, 0)).xy;
                    paperRim /= max(length(paperRim), 1e-4);
                    k = carouselPaperLight(paperNormal, screen - u.center, 2 * s.halfSize.x,
                                             k, paperDistance, paperRim, pixel);
                }
                if (carouselRefinedReflections) {
                    light += albedo * k * entering * exp(-s.sigma * sheet.along);
                } else {
                    light += albedo * k * entering / (1 - f0) * exp(-s.sigma * sheet.along);
                }
            } else {
                clearPlastic = 1;
                float3 exitNormal = float3(0, 0, inside.z < 0 ? -1 : 1);
                float toExit = abs(inside.z) > 1e-4 ? ((inside.z < 0 ? -t : 0.0) - point.z) / inside.z : 3 * t;
                float3 absorbed = exp(-s.sigma * clamp(toExit, 0.0, 3 * t));
                float leaving = 1 - carouselFresnel(abs(inside.z), s.ior);
                float3 trappedDirection = carouselSlabToWorld(reflect(inside, exitNormal), c, sn, u.rotation);
                if (carouselSceneDepth) trappedDirection = normalize((scene.receiverToScene *
                    float4(reflect(inside, exitNormal), 0)).xyz);
                float3 trapped = studio.sample(environment, trappedDirection, level(slab.maxLod)).rgb;
                light += entering * (1 - leaving) * absorbed * trapped;
                through = entering * leaving * absorbed;
            }
        }
    }
    if (carouselFrosted) {
        // A small neutral scattering component belongs to the plastic alone;
        // opaque paper has zero through-light and receives none of this frost.
        float3 scattered = through * 0.20;
        light += scattered * float3(0.72, 0.78, 0.84);
        through -= scattered;
    }
    if (carouselSmoked) through *= float3(0.68, 0.76, 0.82);
    float refractionFootprint = pixel;
    if (!carouselSceneDepth && carouselRefractiveEdges && bleed.count > 0 && bleed.strength > 0) {
        // The circular lens also expands texture detail around curved contours.
        // Derivatives precede the coverage branch, as in the reference's backdrop
        // path, so the selected mip covers the complete warped pixel footprint.
        float t = saturate(-bleedDistance / max(bleed.height, 1.0));
        float2 refractedScreen = screen + bleed.height * (1 - sqrt(t * (2 - t))) * bleedNormal;
        refractionFootprint = max(pixel, max(length(dfdx(refractedScreen)), length(dfdy(refractedScreen))));
    }
    if (carouselSceneDepth && !carouselSkipHiddenShading) {
        sceneVisibility = carouselScenePrimaryVisibility(screen, visibilityPoint, scene);
    }
    // Optical helpers still evaluate every hardware derivative before their
    // zero-coverage exit. Fractional visibility keeps the full optical calculation.
    float opticalCoverage = coverage * sceneVisibility;
    float4 sceneBled = 0;
    if (carouselSceneDepth) {
        sceneBled = carouselSceneBleed(opticalPoint, s, bleedDistance, opticalCoverage, bleed, scene, slab,
                                      sceneImages, sceneVideos, sampling, cardColor);
    }
    float baselineWeight = 0;
    // The neighbours' colours bleed in at the edge: mixed over all the card shows there,
    // the drawable it keeps included.
    if (coverage > 0) {
        if (carouselRefractiveEdges) {
            carouselLaminateRim(bleedDistance, s.bevel, pixel, bleedNormal, materialNov, slab, light, through);
        }
        float4 bled;
        if (carouselSceneDepth) {
            bled = sceneBled;
        } else if (carouselRefractiveEdges) {
            bled = carouselRefraction(screen, bleedDistance, bleedNormal, pixel, refractionFootprint,
                                      clearPlastic, materialNov, bleed, refraction, neighbourImages,
                                      neighbourVideos, sampling, stock);
        } else {
            bled = carouselBleed(screen, bleedDistance, bleedNormal, pixel, refractionFootprint,
                                  clearPlastic, bleed, neighbourImages, sampling);
        }
        baselineWeight = saturate(bled.a);
        light = mix(light, bled.rgb, baselineWeight);
        through *= 1 - baselineWeight;
    }
    if (carouselPicksUpForeground) {
        carouselSceneReflection(opticalPoint, opticalNormal, s, clearPlastic, opticalCoverage,
            surfaceReflection * (1 - baselineWeight), scene, slab, sceneImages, sceneVideos,
            sampling, cardColor, light);
    }
    if (carouselColorsCard) carouselApplyCardColor(colorPoint, s.halfSize, cardColor, light, through);
    // Over what lies behind: the light is added, and the drawable kept by `through`.
    CarouselSlabOutput output;
    float opacity = coverage * u.opacity;
    float3 keep = 1 - opacity + opacity * through;
    float keepAll = (keep.r + keep.g + keep.b) / 3;
    output.color = float4(light * opacity * u.tint, 1 - keepAll);
    if ((carouselPromoted || carouselSoftShadows) && u.shadowAlpha > 0 &&
        (!carouselSoftShadows || keepAll > 0)) {
        float shadow;
        if (carouselSoftShadows) {
            shadow = carouselLayeredShadow(facePoint, u);
        } else {
            float sd = max(0.0, roundedDistance(facePoint - u.shadowOffset, u.frameHalf, u.frameRadius));
            shadow = u.shadowAlpha * exp(-sd * sd * u.shadowFalloff);
        }
        output.color.a += keepAll * shadow;
        keep *= 1 - shadow;
        keepAll *= 1 - shadow;
    }
    if (output.color.a < 0.0005 && all(output.color.rgb < 0.0005)) discard_fragment();
    if (!carouselSceneDepth && carouselPromoted && u.occluderCount > 0 && u.occlusion > 0) {
        float reveal = 1;
        for (uint index = 0; index < u.occluderCount; ++index) {
            constant CarouselOccluderUniforms &occluder = occluders[index];
            float2 delta = screen - occluder.center;
            float cosine = occluder.rotation.x, sine = occluder.rotation.y;
            float2 q = float2(delta.x * cosine + delta.y * sine, -delta.x * sine + delta.y * cosine);
            float distance = roundedDistance(q, occluder.cardSize * 0.5, occluder.cornerRadius);
            float aa = max(fwidth(distance), 0.35);
            float alpha = (1 - smoothstep(-aa * 0.5, aa * 0.5, distance)) * occluder.opacity;
            reveal *= 1 - u.occlusion * alpha;
        }
        output.color *= reveal;
        keep = reveal * keep + (1 - reveal);
        keepAll = reveal * keepAll + (1 - reveal);
    }
    if (carouselSceneDepth) {
        output.color *= sceneVisibility;
        keep = sceneVisibility * keep + (1 - sceneVisibility);
        keepAll = sceneVisibility * keepAll + (1 - sceneVisibility);
    }
    output.transmission = float4(keep, keepAll);
    return output;
}
