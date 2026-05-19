#include <metal_stdlib>
using namespace metal;

struct BackgroundUniforms {
    float time;
    float level;
    float aspect;
    float beat;
    float lowBand;
    float midBand;
    float highBand;
    float bpm;
};

struct PaletteUniforms {
    float4 primary;
    float4 secondary;
    float4 accent;
    float4 background;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

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

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

fragment float4 background_fragment(VertexOut in [[stage_in]],
                                    constant BackgroundUniforms& u [[buffer(0)]],
                                    constant float* magnitudes [[buffer(1)]],
                                    constant PaletteUniforms& palette [[buffer(2)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;
    float2 p = (uv - 0.5);
    p.x *= u.aspect;

    float lo = clamp(u.lowBand * 6.0, 0.0, 1.5);
    float hi = clamp(u.highBand * 6.0, 0.0, 1.5);
    float bias = clamp((hi - lo) * 0.5, -0.8, 0.8);

    float3 bg = palette.background.rgb;
    float3 baseLow = bg + palette.secondary.rgb * 0.10;
    float3 baseHigh = bg + palette.primary.rgb * 0.10;
    float3 base = mix(baseLow, baseHigh, smoothstep(-0.5, 0.5, bias));

    float r = length(p);
    float drift = 0.5 + 0.5 * sin(u.time * 0.18);
    // Wider, brighter halo so the screen center never reads as a void
    // when foreground modes leave negative space (Aurora gaps,
    // Filament donut, etc.).
    float halo = exp(-r * (2.6 - 0.4 * drift - lo * 1.0));

    float beatRadius = u.beat * 0.55;
    float ring = exp(-pow((r - beatRadius) * 12.0, 2.0)) * u.beat;

    float sparkleField = step(0.997,
        hash21(floor(uv * 220.0) + floor(u.time * 12.0)));
    float sparkle = sparkleField * hi * 1.4;

    float3 col = base
        + halo * 0.30 * palette.primary.rgb
        + ring * palette.accent.rgb * 0.6
        + sparkle * palette.secondary.rgb * 0.55;

    col *= 1.0 - smoothstep(0.78, 1.30, r) * 0.40;

    // Bass-band floor tint, modulated by the lowest log-bin energy.
    float bassFloor = magnitudes[0] * 4.0;
    col += palette.secondary.rgb * 0.18 * bassFloor * pow(1.0 - uv.y, 3.0);

    // Soft dither to prevent banding in deep gradients.
    float n = hash21(uv * 1024.0 + u.time);
    col += (n - 0.5) * (1.0 / 255.0);

    return float4(col, 1.0);
}
