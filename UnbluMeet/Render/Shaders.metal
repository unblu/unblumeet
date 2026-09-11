#include <metal_stdlib>
using namespace metal;

struct TileUniforms {
    float4 rect;      // x, y, width, height in normalised screen space
    float4 uvRect;    // x, y, width, height of the frame region to sample
    float2 sizePx;    // tile size in pixels, for corner rounding
    float  radiusPx;  // 0 = square corners
    float  blurPx;    // shadow softness; unused by tile fragments
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float2 local;   // 0-1 within the quad, for corner rounding
};

// Unit quad positioned by the tile rect. Vertex ids 0-3 form a triangle strip.
vertex VertexOut tile_vertex(uint vid [[vertex_id]],
                             constant TileUniforms &uniforms [[buffer(0)]]) {
    float2 corner = float2((vid == 1 || vid == 3) ? 1.0 : 0.0,
                           (vid == 2 || vid == 3) ? 1.0 : 0.0);

    float x = uniforms.rect.x + corner.x * uniforms.rect.z;
    float y = uniforms.rect.y + corner.y * uniforms.rect.w;

    VertexOut out;
    out.position = float4(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    out.uv = float2(uniforms.uvRect.x + corner.x * uniforms.uvRect.z,
                    uniforms.uvRect.y + corner.y * uniforms.uvRect.w);
    out.local = corner;
    return out;
}

/// Signed distance to a rounded box, in pixels. Negative inside.
static inline float roundedBoxSDF(float2 point, float2 halfSize, float radius) {
    float2 d = abs(point) - (halfSize - radius);
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

/// Coverage for a rounded corner, antialiased over one pixel.
/// radiusPx == 0 returns 1 everywhere, so square tiles cost nothing.
static inline float cornerAlpha(float2 local, float2 sizePx, float radiusPx) {
    if (radiusPx <= 0.0) return 1.0;
    float2 halfSize = sizePx * 0.5;
    float dist = roundedBoxSDF(local * sizePx - halfSize, halfSize, radiusPx);
    return saturate(0.5 - dist);
}

// Soft drop shadow behind a rounded tile.
//
// The quad is larger than the tile by the blur radius on every side, and the
// shape is that much smaller than the quad — measuring against the quad drew a
// flat slab with a hard edge, which reads as a second rectangle rather than a
// shadow. Alpha then eases out across the blur instead of falling off
// linearly, so there is no visible band where it stops.
fragment float4 tile_fragment_shadow(VertexOut in [[stage_in]],
                                     constant TileUniforms &uniforms [[buffer(0)]]) {
    float blur = max(uniforms.blurPx, 1.0);
    float2 halfQuad = uniforms.sizePx * 0.5;
    float2 halfShape = max(halfQuad - blur, float2(1.0));
    float dist = roundedBoxSDF(in.local * uniforms.sizePx - halfQuad,
                               halfShape, uniforms.radiusPx);
    float fade = 1.0 - smoothstep(0.0, blur, dist);
    return float4(0.0, 0.0, 0.0, fade * fade * 0.55);
}

// Packed BGRA — what VideoFrame.toCVPixelBuffer() produces when it converts a
// software-decoded I420 frame. Non-planar, so no colour conversion needed.
fragment float4 tile_fragment_bgra(VertexOut in [[stage_in]],
                                   constant TileUniforms &uniforms [[buffer(0)]],
                                   texture2d<float> colorTexture [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    float alpha = cornerAlpha(in.local, uniforms.sizePx, uniforms.radiusPx);
    if (alpha <= 0.0) discard_fragment();
    return float4(colorTexture.sample(textureSampler, in.uv).rgb, alpha);
}

// I420 (tri-planar 4:2:0) to RGB, BT.709 video range.
// Software decoders (VP8/VP9) produce this; hardware H.264 produces NV12.
fragment float4 tile_fragment_i420(VertexOut in [[stage_in]],
                                   constant TileUniforms &uniforms [[buffer(0)]],
                                   texture2d<float> yTexture [[texture(0)]],
                                   texture2d<float> uTexture [[texture(1)]],
                                   texture2d<float> vTexture [[texture(2)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);

    float y = yTexture.sample(textureSampler, in.uv).r;
    float u = uTexture.sample(textureSampler, in.uv).r - 0.5;
    float v = vTexture.sample(textureSampler, in.uv).r - 0.5;

    y = (y - 16.0 / 255.0) * (255.0 / 219.0);

    float3 rgb;
    rgb.r = y + 1.5748 * v;
    rgb.g = y - 0.1873 * u - 0.4681 * v;
    rgb.b = y + 1.8556 * u;

    float alpha = cornerAlpha(in.local, uniforms.sizePx, uniforms.radiusPx);
    if (alpha <= 0.0) discard_fragment();
    return float4(saturate(rgb), alpha);
}

// NV12 (bi-planar 4:2:0) to RGB, BT.709 video range.
fragment float4 tile_fragment(VertexOut in [[stage_in]],
                              constant TileUniforms &uniforms [[buffer(0)]],
                              texture2d<float> yTexture [[texture(0)]],
                              texture2d<float> cbcrTexture [[texture(1)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);

    float y = yTexture.sample(textureSampler, in.uv).r;
    float2 cbcr = cbcrTexture.sample(textureSampler, in.uv).rg - float2(0.5, 0.5);

    y = (y - 16.0 / 255.0) * (255.0 / 219.0);

    float3 rgb;
    rgb.r = y + 1.5748 * cbcr.y;
    rgb.g = y - 0.1873 * cbcr.x - 0.4681 * cbcr.y;
    rgb.b = y + 1.8556 * cbcr.x;

    float alpha = cornerAlpha(in.local, uniforms.sizePx, uniforms.radiusPx);
    if (alpha <= 0.0) discard_fragment();
    return float4(saturate(rgb), alpha);
}


struct MarkUniforms {
    float4 color;
};

vertex float4 mark_vertex(uint vid [[vertex_id]],
                          constant float2 *points [[buffer(0)]]) {
    float2 p = points[vid];
    return float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
}

fragment float4 mark_fragment(constant MarkUniforms &uniforms [[buffer(0)]]) {
    return uniforms.color;
}
