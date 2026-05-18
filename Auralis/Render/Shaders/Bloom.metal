#include <metal_stdlib>
using namespace metal;

struct BloomUniforms {
    float time;
    float aspect;
    float level;
    float loudness;
    float lowBand;
    float midBand;
    float highBand;
    float beat;
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

vertex FSVertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 p = positions[vid];
    FSVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = (p + 1.0) * 0.5;
    return out;
}

static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fragment float4 bloom_fragment(FSVertexOut in [[stage_in]],
                               constant BloomUniforms& u [[buffer(0)]],
                               constant float* magnitudes [[buffer(1)]],
                               constant PaletteUniforms& palette [[buffer(2)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;
    float2 p = (uv - 0.5);
    p.x *= u.aspect;

    float midKick = clamp(u.midBand * 6.0, 0.0, 1.5);
    float lowKick = clamp(u.lowBand * 6.0, 0.0, 1.5);
    float blobMerge = 0.07 + 0.07 * midKick;
    float baseRadius = 0.055 + 0.04 * lowKick;

    // Twelve small metaballs, well-separated on layered orbits so the
    // smin field reads as a constellation rather than a single disc.
    float sdf = 1e9;
    for (int i = 0; i < 12; ++i) {
        float fi = float(i);
        float phase = u.time * (0.16 + 0.05 * fi * 0.5) + fi * 1.1;
        float orbit = 0.36 + 0.16 * sin(phase * 0.27 + fi * 0.9);
        float2 c = float2(
            cos(phase + sin(fi * 0.7)) * orbit,
            sin(phase * 1.21 + cos(fi * 0.4)) * orbit * 0.82
        );
        float magContribution = magnitudes[uint(fi * 5.0) % 64u] * 0.18;
        float r = baseRadius + magContribution + 0.010 * sin(u.time * 1.7 + fi);
        sdf = smin(sdf, length(p - c) - r, blobMerge);
    }

    // Beat shockwave: a soft expanding ring centered.
    float shock = exp(-pow((length(p) - u.beat * 0.65) * 18.0, 2.0)) * u.beat * 0.75;

    // Field intensity from SDF (interior glow + soft edge).
    float interior = smoothstep(0.0, -0.06, sdf);
    float edge = exp(-pow(max(sdf, 0.0) * 14.0, 2.0));

    float3 cInner = mix(palette.secondary.rgb, palette.accent.rgb, midKick * 0.55);
    float3 cOuter = palette.primary.rgb;

    float3 col = mix(cOuter, cInner, interior);
    float bloom = interior * 0.85 + edge * 0.55 + shock * 1.1;

    float3 final = col * bloom + palette.accent.rgb * shock * 0.25;

    float alpha = clamp(bloom * 0.55 + shock * 0.30, 0.0, 1.0);
    return float4(final, alpha);
}
