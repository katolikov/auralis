#include <metal_stdlib>
using namespace metal;

struct FilamentUniforms {
    float time;
    float aspect;
    float level;
    float lowBand;
    float midBand;
    float highBand;
    float beat;
    float loudness;
    uint particleCount;
    float flowStrength;
    float pointSize;
    float lifetime;
};

struct PaletteUniforms {
    float4 primary;
    float4 secondary;
    float4 accent;
    float4 background;
};

struct FilamentOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float alpha;
};

static inline float hash11(float n) {
    return fract(sin(n) * 43758.5453);
}

static inline float2 hash22(float n) {
    return float2(
        fract(sin(n) * 43758.5453),
        fract(sin(n * 1.7) * 12541.97))
        * 2.0 - 1.0;
}

static inline float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash11(dot(i, float2(1.0, 57.0)));
    float b = hash11(dot(i + float2(1.0, 0.0), float2(1.0, 57.0)));
    float c = hash11(dot(i + float2(0.0, 1.0), float2(1.0, 57.0)));
    float d = hash11(dot(i + float2(1.0, 1.0), float2(1.0, 57.0)));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Pseudo-curl: rotate gradient of a scalar noise field 90 degrees.
static inline float2 curl2(float2 p) {
    const float eps = 0.05;
    float n1 = noise2(p + float2(0, eps));
    float n2 = noise2(p - float2(0, eps));
    float n3 = noise2(p + float2(eps, 0));
    float n4 = noise2(p - float2(eps, 0));
    return float2(n1 - n2, -(n3 - n4)) / (2.0 * eps);
}

vertex FilamentOut filament_vertex(uint vid [[vertex_id]],
                                   constant FilamentUniforms& u [[buffer(0)]],
                                   constant PaletteUniforms& palette [[buffer(2)]]) {
    float seed = float(vid) + 0.5;
    float n = float(vid) / float(max(u.particleCount, 1u));

    float age = fmod(u.time + hash11(seed * 0.013) * u.lifetime, u.lifetime);
    float lifeT = age / u.lifetime;

    float angle = hash11(seed * 0.0073) * 6.28318;
    // Bias toward the center via radius² so uniform sampling doesn't
    // produce ring-heavy distributions on a 2D plane.
    float radiusRoll = hash11(seed * 0.0193);
    float radius = mix(0.0, 1.05, radiusRoll * radiusRoll);
    float2 spawn = float2(cos(angle), sin(angle)) * radius;

    // Per-particle "speed class". Cubic distribution means most
    // particles are nearly static (filling the interior with a
    // soft cloud) while a small tail of fast particles makes the
    // visible swirls. Multi-scale noise prevents the entire fast
    // population from clustering at one characteristic radius.
    float speedClass = hash11(seed * 0.041);
    float speedMul = speedClass * speedClass * speedClass;
    float perParticleFlow = u.flowStrength * (0.04 + speedMul * 1.10);

    // Per-particle spatial scale so curl eddies don't all line up.
    float scale = 1.7 + hash11(seed * 0.083) * 3.4;
    float2 flowA = curl2(spawn * scale + float2(u.time * 0.12, -u.time * 0.08));
    float2 flowB = curl2(spawn * (scale * 2.7) + float2(u.time * 0.05, u.time * 0.09));
    float2 flow = (flowA * 0.78 + flowB * 0.22) * perParticleFlow;

    // Second-order step for a slightly arched trajectory.
    float2 midPos = spawn + flow * (age * 0.5);
    float2 flow2 = curl2(midPos * scale + float2(u.time * 0.18, u.time * 0.22));
    float2 position = spawn + flow * age + flow2 * age * 0.4 * perParticleFlow;

    // Beat thrust outward, scaled by speedClass so the slow center
    // population isn't shoved into the ring.
    float beatPush = u.beat * 0.12 * lifeT * speedClass;
    position += normalize(position + 1e-3) * beatPush;

    // Subtle vertical sway from low band.
    position.y += sin(u.time * 1.7 + seed * 0.21) * 0.04 * (0.5 + u.lowBand * 4.0);

    // Lifetime fade-in/out.
    float fade = sin(lifeT * 3.14159);

    // Project: scale to viewport and correct aspect.
    float2 screen = position * 0.78;
    screen.x /= max(u.aspect, 0.001);

    FilamentOut out;
    out.position = float4(screen, 0.0, 1.0);
    out.pointSize = u.pointSize * (0.6 + 0.4 * fade);
    out.alpha = fade * (0.45 + u.loudness * 1.5);

    // Color by particle index — sweeps through palette.
    float t = fract(n + hash11(seed * 0.0023));
    float3 col = mix(palette.primary.rgb, palette.secondary.rgb, t);
    col = mix(col, palette.accent.rgb, smoothstep(0.7, 1.0, t));
    col *= 1.0 + u.beat * 0.6;
    out.color = col;
    return out;
}

fragment float4 filament_fragment(FilamentOut in [[stage_in]],
                                  float2 pc [[point_coord]]) {
    float2 d = pc - 0.5;
    float r = dot(d, d) * 4.0;
    float falloff = exp(-r * 4.0);
    if (falloff < 0.005) discard_fragment();
    return float4(in.color * falloff, in.alpha * falloff);
}
