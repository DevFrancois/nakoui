//
//  PaneFunnel.metal
//  MapsIOS26BottomSheet
//

#include <metal_stdlib>
using namespace metal;

// A bounded horizontal bend. Vertical travel is an affine transform of the whole card,
// so the gradient and background reach the destination together.
[[ stitchable ]] float2 paneFunnel(float2 position, float4 bounds, float amount) {
    float row = clamp((position.y - bounds.y) / max(bounds.w, 1.0f), 0.0f, 1.0f);
    float neck = (1.0f - row) * (1.0f - row);
    float width = max(1.0f - amount * neck, 0.4f);
    float center = bounds.x + bounds.z * 0.5f;
    return float2(center + (position.x - center) / width, position.y);
}
