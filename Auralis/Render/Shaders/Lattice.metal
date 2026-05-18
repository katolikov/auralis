#include <metal_stdlib>
using namespace metal;

struct LatticeUniforms {
    float4x4 viewProjection;
    float time;
    float lowBand;
    float midBand;
    float highBand;
    float beat;
    float loudness;
    float spacing;
    float cellWidth;
    uint cols;
    uint rows;
    float audioGain;
};

struct PaletteUniforms {
    float4 primary;
    float4 secondary;
    float4 accent;
    float4 background;
};

struct LatticeOut {
    float4 position [[position]];
    float height;
    float2 cellID;
    float depth;
};

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

vertex LatticeOut lattice_vertex(uint vid [[vertex_id]],
                                 uint iid [[instance_id]],
                                 constant float3* cube [[buffer(0)]],
                                 constant LatticeUniforms& u [[buffer(1)]],
                                 constant float* magnitudes [[buffer(2)]]) {
    uint instX = iid % u.cols;
    uint instY = iid / u.cols;

    // Diagonal mapping spreads adjacent cells across the spectrum.
    uint magIdx = (instX * 3u + instY * 2u) % 64u;
    float magnitude = magnitudes[magIdx];
    float pulse = 0.4 + 0.6 * sin(u.time * 1.2 + float(instX + instY) * 0.4);
    float height = (0.04 + magnitude * u.audioGain) * pulse + 0.08 * u.loudness + 0.2 * u.beat;

    float halfCols = float(u.cols - 1u) * 0.5;
    float halfRows = float(u.rows - 1u) * 0.5;
    float3 cellOffset = float3(
        (float(instX) - halfCols) * u.spacing,
        0.0,
        (float(instY) - halfRows) * u.spacing
    );

    float3 vp = cube[vid];
    vp.x *= u.cellWidth;
    vp.z *= u.cellWidth;
    vp.y *= height;

    float3 worldPos = cellOffset + vp;

    LatticeOut out;
    out.position = u.viewProjection * float4(worldPos, 1.0);
    out.height = height;
    out.cellID = float2(float(instX), float(instY));
    out.depth = worldPos.z + worldPos.x * 0.4;
    return out;
}

fragment float4 lattice_fragment(LatticeOut in [[stage_in]],
                                 constant LatticeUniforms& u [[buffer(1)]],
                                 constant PaletteUniforms& palette [[buffer(2)]]) {
    // Gradient along cell-height; tint by cell ID.
    float t = clamp(in.height * 1.6, 0.0, 1.0);
    float3 col = mix(palette.primary.rgb, palette.accent.rgb, t);

    // Inject hue variation across X (frequency) cells.
    float hueBias = hash21(in.cellID + 31.7);
    col = mix(col, palette.secondary.rgb, hueBias * 0.35);

    // Subtle depth fade.
    float depthFade = clamp(1.0 - in.depth * 0.06, 0.4, 1.0);
    col *= depthFade;

    // Add an emissive highlight at the top of each rod.
    float tip = smoothstep(0.55, 1.0, in.height) * 0.6;
    col += palette.accent.rgb * tip;

    float alpha = clamp(0.55 + in.height * 0.55, 0.0, 1.0);

    return float4(col, alpha);
}
