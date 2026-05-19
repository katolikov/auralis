#include <metal_stdlib>
using namespace metal;

struct AuroraVertex {
    float3 position;
    float2 uv;
};

struct AuroraUniforms {
    float4x4 viewProjection;
    float time;
    float level;
    float lowBand;
    float midBand;
    float highBand;
    float beat;
    float loudness;
    float ribbonIndex;
};

struct PaletteUniforms {
    float4 primary;
    float4 secondary;
    float4 accent;
    float4 background;
};

struct AuroraOut {
    float4 position [[position]];
    float2 uv;
    float displacement;
    float ribbonPhase;
};

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// Smoothstep-interpolated value noise.
static inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += vnoise(p) * amp;
        p = p * 2.07 + float2(13.1, 9.7);
        amp *= 0.5;
    }
    return v;
}

vertex AuroraOut aurora_vertex(uint vid [[vertex_id]],
                               constant AuroraVertex* verts [[buffer(0)]],
                               constant AuroraUniforms& u [[buffer(1)]]) {
    AuroraVertex v = verts[vid];
    float t = u.time;
    float x = v.position.x;
    float z = v.position.z;

    // Layered sinusoidal sheet, modulated by the bass envelope.
    float lo = clamp(u.lowBand * 5.5, 0.0, 2.0);
    float mid = clamp(u.midBand * 4.5, 0.0, 1.5);
    float macro = sin(x * 0.55 + t * 0.7 + u.ribbonIndex * 1.3) * 0.55;
    float micro = sin(x * 1.85 - t * 0.45 + z * 1.7) * 0.28;
    float ripple = sin(x * 4.2 + t * 1.8) * 0.10 * (0.4 + mid);
    float depthCurl = cos(z * 3.0 + t * 0.6) * 0.12;

    float displacement = (macro + micro + ripple + depthCurl);
    displacement *= 0.55 + 0.7 * lo + 0.2 * u.beat;

    // Heave the depth so ribbons feel volumetric.
    float pz = z + sin(x * 0.7 + t * 0.35) * 0.18;
    float py = displacement;

    AuroraOut out;
    out.position = u.viewProjection * float4(x, py, pz, 1.0);
    out.uv = v.uv;
    out.displacement = displacement;
    out.ribbonPhase = u.ribbonIndex;
    return out;
}

fragment float4 aurora_fragment(AuroraOut in [[stage_in]],
                                constant AuroraUniforms& u [[buffer(1)]],
                                constant PaletteUniforms& palette [[buffer(2)]]) {
    float2 uv = in.uv;
    float hi = clamp(u.highBand * 5.5, 0.0, 1.5);

    // Sweep color across the ribbon length with audio-reactive bias.
    float t = uv.x + sin(u.time * 0.4 + in.ribbonPhase) * 0.12;
    float3 deep = palette.secondary.rgb;
    float3 mid = palette.primary.rgb;
    float3 tip = palette.accent.rgb;
    float3 col = mix(deep, mid, smoothstep(0.0, 0.6, t));
    col = mix(col, tip, smoothstep(0.55, 1.0, t));

    // Filament streaks along ribbon length; FFT-noise pattern.
    float streak = fbm(float2(uv.x * 6.0 + u.time * 0.3 + in.ribbonPhase * 1.7,
                              uv.y * 0.5 + u.time * 0.04));
    float streakMask = smoothstep(0.45, 0.95, streak);

    // Soft band along ribbon depth (UV.y) — gives volumetric falloff.
    // 2.1 keeps edges visible enough (≈0.33 at uv.y=0/1) that four
    // overlapping ribbons fill the center without carving an oval
    // void, but tight enough that additive stacking doesn't saturate.
    float depthBand = exp(-pow((uv.y - 0.5) * 2.1, 2.0));

    // Audio-reactive intensity envelope.
    float envelope = 1.0 + abs(in.displacement) * 1.4 + u.beat * 0.9 + u.loudness * 2.0;
    float intensity = depthBand * (0.45 + 0.65 * streakMask) * envelope;

    // Add high-frequency sparkle along the filament crest.
    float sparkle = step(0.995, hash21(uv * 240.0 + u.time)) * hi;

    float3 finalColor = col * intensity + tip * sparkle * 0.9;

    // Per-ribbon hue rotation for variety between the three layers.
    float hueShift = in.ribbonPhase * 0.16;
    finalColor = mix(finalColor, tip * intensity, hueShift);

    // Alpha drives the additive contribution. Tuned so four ribbons
    // with the 2.1 depth-band compose into glowing sheets without
    // saturating to white at the brightest overlapping crests.
    float alpha = clamp(intensity * 0.17, 0.0, 1.0);

    return float4(finalColor, alpha);
}
