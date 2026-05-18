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

    float midKick = clamp(u.midBand * 6.0, 0.0, 2.0);
    float lowKick = clamp(u.lowBand * 6.0, 0.0, 2.0);
    float blobMerge = 0.20 + 0.18 * midKick;
    float baseRadius = 0.16 + 0.08 * lowKick;

    // Eight metaballs orbiting on lissajous curves.
    float sdf = 1e9;
    for (int i = 0; i < 8; ++i) {
        float fi = float(i);
        float phase = u.time * (0.18 + 0.04 * fi) + fi * 1.3;
        float orbit = 0.28 + 0.05 * sin(phase * 0.6 + fi);
        float2 c = float2(
            cos(phase + sin(fi)) * orbit,
            sin(phase * 1.27 + cos(fi)) * orbit * 0.78
        );
        float magContribution = magnitudes[uint(fi) * 8u] * 0.4;
        float r = baseRadius + magContribution + 0.012 * sin(u.time * 1.7 + fi);
        sdf = smin(sdf, length(p - c) - r, blobMerge);
    }

    // Beat shockwave: a soft expanding ring centered.
    float shock = exp(-pow((length(p) - u.beat * 0.7) * 14.0, 2.0)) * u.beat;

    // Field intensity from SDF (interior glow + soft edge).
    float interior = smoothstep(0.0, -0.12, sdf);
    float edge = exp(-pow(max(sdf, 0.0) * 9.0, 2.0));

    float3 cInner = mix(palette.secondary.rgb, palette.accent.rgb, midKick * 0.5);
    float3 cOuter = palette.primary.rgb;

    float3 col = mix(cOuter, cInner, interior);
    float bloom = interior * 1.4 + edge * 0.85 + shock * 1.6;

    float3 final = col * bloom + palette.accent.rgb * shock * 0.4;

    // Alpha controls blending over the background pass.
    float alpha = clamp(bloom * 0.9 + shock * 0.4, 0.0, 1.0);

    return float4(final, alpha);
}
