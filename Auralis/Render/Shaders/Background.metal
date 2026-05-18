#include <metal_stdlib>
using namespace metal;

// Keep this struct byte-compatible with `BackgroundUniforms` in Swift.
struct BackgroundUniforms {
    float time;
    float level;
    float aspect;
    float _pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen-triangle trick: three vertices, no buffer, covers the
// entire viewport with one degenerate triangle. uv ranges 0..1.
vertex VertexOut background_vertex(uint vid [[vertex_id]],
                                   constant BackgroundUniforms& u [[buffer(0)]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 p = positions[vid];
    VertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = (p + 1.0) * 0.5;
    return out;
}

// Editorial placeholder background. Establishes the visual register
// for Milestone 1: deep cool gradient, subtle parallax noise, a slow
// breathing halo that responds to broadband audio level. This shader
// is replaced by Aurora in Milestone 4.
fragment float4 background_fragment(VertexOut in [[stage_in]],
                                    constant BackgroundUniforms& u [[buffer(0)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;

    float2 p = (uv - 0.5);
    p.x *= u.aspect;

    // Twin deep-space gradient stops, mixed along screen-Y.
    float3 cool = float3(0.020, 0.028, 0.052);
    float3 warm = float3(0.055, 0.060, 0.105);
    float3 base = mix(cool, warm, smoothstep(0.0, 1.0, uv.y));

    // Drifting low-frequency glow centered slightly above middle.
    float2 c = float2(0.0, -0.05);
    float r = length(p - c);
    float drift = 0.5 + 0.5 * sin(u.time * 0.18);
    float halo = exp(-r * (4.5 - 0.8 * drift));

    float energy = clamp(u.level * 6.0, 0.0, 1.0);
    float pulse = smoothstep(0.0, 1.0, energy);
    float radial = exp(-r * (3.2 - 1.6 * pulse)) * pulse;

    float3 accent = float3(0.42, 0.58, 0.95);
    float3 col = base + halo * 0.10 + radial * accent * 0.55;

    // Soft top-left highlight to evoke a polished editorial frame.
    float corner = exp(-length(uv - float2(0.18, 0.18)) * 3.8) * 0.06;
    col += corner;

    // Fine film-grain dither to break up banding.
    float n = fract(sin(dot(uv * 1024.0, float2(12.9898, 78.233)) + u.time) * 43758.5453);
    col += (n - 0.5) * (1.0 / 255.0);

    return float4(col, 1.0);
}
