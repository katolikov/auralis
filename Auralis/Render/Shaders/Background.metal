#include <metal_stdlib>
using namespace metal;

// Keep byte-compatible with `BackgroundUniforms` in Swift.
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

// Editorial placeholder background carrying the M2 audio features.
fragment float4 background_fragment(VertexOut in [[stage_in]],
                                    constant BackgroundUniforms& u [[buffer(0)]],
                                    constant float* magnitudes [[buffer(1)]]) {
    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;
    float2 p = (uv - 0.5);
    p.x *= u.aspect;

    float lo = clamp(u.lowBand * 6.0, 0.0, 1.5);
    float hi = clamp(u.highBand * 6.0, 0.0, 1.5);
    float bias = clamp((hi - lo) * 0.5, -0.8, 0.8);

    float3 cool = float3(0.020, 0.030, 0.060);
    float3 warm = float3(0.060, 0.025, 0.040);
    float3 base = mix(warm, cool, smoothstep(-0.5, 0.5, bias));

    float r = length(p);
    float drift = 0.5 + 0.5 * sin(u.time * 0.18);
    float halo = exp(-r * (4.0 - 0.5 * drift - lo * 1.2));

    float beatRadius = u.beat * 0.55;
    float ring = exp(-pow((r - beatRadius) * 12.0, 2.0)) * u.beat;

    float sparkleField = step(0.997,
        hash21(floor(uv * 220.0) + floor(u.time * 12.0)));
    float sparkle = sparkleField * hi * 1.4;

    float3 accentCool = float3(0.45, 0.65, 0.95);
    float3 accentHot = float3(0.95, 0.55, 0.78);
    float3 accent = mix(accentHot, accentCool, smoothstep(-0.5, 0.5, bias));

    float3 col = base + halo * 0.16 * accent
                 + ring * float3(0.85, 0.92, 1.0) * 0.55
                 + sparkle * float3(1.0, 0.9, 1.0) * 0.6;

    col *= 1.0 - smoothstep(0.7, 1.25, r) * 0.45;

    // Read the lowest log-bin to tint screen-bottom; reinforces bass presence.
    float bassFloor = magnitudes[0] * 4.0;
    col += float3(0.05, 0.04, 0.10) * bassFloor * pow(1.0 - uv.y, 3.0);

    float n = hash21(uv * 1024.0 + u.time);
    col += (n - 0.5) * (1.0 / 255.0);
    return float4(col, 1.0);
}
