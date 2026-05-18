#include <metal_stdlib>
using namespace metal;

struct HaloUniforms {
    float time;
    float aspect;
    float loudness;
    float lowBand;
    float midBand;
    float highBand;
    float beat;
    float level;
};

struct PaletteUniforms {
    float4 primary;
    float4 secondary;
    float4 accent;
    float4 background;
};

struct FSVertexOut {
    float4 position [[position]];
    float2 uv;
};

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

fragment float4 halo_fragment(FSVertexOut in [[stage_in]],
                              constant HaloUniforms& u [[buffer(0)]],
                              constant PaletteUniforms& palette [[buffer(2)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;
    float2 p = (uv - 0.5);
    p.x *= u.aspect;

    // Soft gradient wash: vertical primary->secondary, slight low-band warmth at bottom.
    float3 base = palette.background.rgb;
    base = mix(base + palette.secondary.rgb * 0.05,
               base + palette.primary.rgb * 0.07,
               smoothstep(0.0, 1.0, uv.y));
    base += palette.secondary.rgb * 0.06 * pow(1.0 - uv.y, 3.0) * (0.5 + u.lowBand * 3.5);

    // Editorial torus: superellipse-warped circle.
    float angle = atan2(p.y, p.x);
    float warp =
        0.018 * sin(angle * 4.0 + u.time * 0.30) * (0.4 + u.midBand * 2.5)
        + 0.012 * sin(angle * 7.0 - u.time * 0.21);
    float radius = 0.30 + u.loudness * 0.10 + u.beat * 0.05 + warp;

    float r = length(p);
    float thickness = 0.022 + u.loudness * 0.018;
    float ring = smoothstep(thickness, 0.0, abs(r - radius));

    // Soft inner glow.
    float inner = smoothstep(radius + 0.18, radius - 0.02, r) *
                  smoothstep(radius - 0.22, radius - 0.02, r);

    // Outer aura.
    float outer = smoothstep(radius + 0.20, radius + 0.02, r) *
                  smoothstep(radius + 0.02, radius + 0.20, r);

    float3 ringCol = mix(palette.accent.rgb, palette.primary.rgb, 0.4);
    float3 innerCol = palette.primary.rgb;
    float3 outerCol = palette.secondary.rgb;

    float3 col = base;
    col += inner * innerCol * 0.30;
    col += outer * outerCol * 0.10;
    col += ring * ringCol * 1.55;

    // Beat shimmer: very fine sparkles inside the ring.
    float sparkleField = step(0.997,
        hash21(floor(uv * 480.0) + floor(u.time * 9.0)));
    float sparkle = sparkleField * u.highBand * inner * 1.4;
    col += sparkle * palette.accent.rgb;

    // Vignette
    col *= 1.0 - smoothstep(0.55, 1.0, r) * 0.45;

    float n = hash21(uv * 1024.0 + u.time);
    col += (n - 0.5) * (1.0 / 255.0);

    return float4(col, 1.0);
}
