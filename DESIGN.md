# DESIGN.md

Internal notes on how Auralis turns sound into picture. Treat this as
the working spec — the code is the source of truth.

---

## Audio pipeline

```
SCStream (Music.app, audio only)
  └─ CMSampleBuffer  (Float32, 48 kHz, stereo, non-interleaved)
       └─ mono mix  (L + R) * 0.5   via vDSP_vadd + vsmul
            └─ 2048-sample ring buffer  (Auralis/Audio/SystemAudioCapture.swift)
                 └─ Hann window  vDSP_hann_window(NORM)
                      └─ split-complex pack  vDSP_ctoz
                           └─ in-place real FFT  vDSP_fft_zrip
                                └─ magnitudes  vDSP_zvabs → / N
                                     ├─ LogBinner          → 64 log-spaced bins (20 Hz–20 kHz)
                                     ├─ BandComputer       → low / mid / high band energy + A-weighting
                                     └─ OnsetDetector      → spectral-flux + adaptive median+MAD
                                          └─ envelope (exp decay τ ≈ 0.18 s) + BPM estimate
                                               └─ AudioFeatures yield → AsyncStream
```

Frame rate: hop = 1024 → ~46.9 features/sec at 48 kHz. The renderer
samples whatever's most recent each draw call; backpressure is handled
by `AsyncStream.bufferingPolicy(.bufferingNewest(2))`.

### A-weighted loudness

A coarse approximation, not a true IEC-651 A-curve. Weighted band sum:

```
loudness = (0.158·low + 1.0·mid + 0.708·high) / (1.0 + 0.158 + 0.708)
```

This is enough perceptual correction for visualization dynamics; we
don't need broadcast-grade metering.

### Onset / beat

Spectral flux `Σ max(0, mag_t[i] − mag_{t-1}[i])` measured against a
rolling 43-frame (~900 ms) history. Threshold is **median + 1.6·MAD**
of the flux history — adaptive enough to track quiet sections without
falsing on the loud ones. A 180 ms refractory period suppresses
double-triggers. BPM is the inverse-mean of the last 16 inter-onset
intervals, clamped to 40–240.

### Smoothing constants (`AudioCaptureController`)

| Feature  | Attack | Release | Notes                                |
| -------- | ------ | ------- | ------------------------------------ |
| level    | 0.45   | 0.10    | Broadband RMS                        |
| loudness | 0.45   | 0.10    | A-weighted                           |
| low      | 0.45   | 0.10    | 20–250 Hz                            |
| mid      | 0.45   | 0.10    | 250 Hz–4 kHz                         |
| high     | 0.45   | 0.10    | 4 kHz–16 kHz                         |
| beat     | 0.90   | 0.10    | Snap-up so onsets feel instantaneous |

Asymmetric attack/release prevents the meters and shaders from
jittering on transients while still tracking sustained changes
quickly.

---

## Palette extraction

`Auralis/NowPlaying/PaletteExtractor.swift`.

1. Downsample artwork to 32 × 32 (sRGB, premultiplied) via CG.
2. Seed k-means with **k-means++** — first center is the median pixel,
   subsequent centers are picked as the point with maximum squared
   distance to any existing center.
3. Run up to 12 Lloyd iterations; bail early if total movement
   < 1e-3 in linear RGB space.
4. Rank centers by a presence score:

   ```
   score = 0.65 · chroma + 0.20 · value + 0.15 · max(0, 1 − 2·|value − 0.55|)
   ```

   Chroma = `max(r,g,b) − min(r,g,b)`. Value = `max(r,g,b)`. The bias
   term penalizes near-black and near-white extremes — those rarely
   make good accent colors even when statistically dominant.

`Theme` keeps a *target* and *current* `Snapshot` (primary, secondary,
accent, background) and interpolates at ~30 Hz with t = 0.06 per tick.
This makes the visualizer glide between palettes instead of cutting,
even at fast track changes.

Background colour is the darkest extracted cluster centre mixed 82 %
toward black, then nudged by a small ambient floor `(0.012, 0.014,
0.022)` to keep the screen from collapsing to pure black on artwork
without dark pixels.

---

## Feature → shader uniform table

Each mode receives a `VisualizerFrame` containing `time`, `aspect`,
the raw `AudioFeatures`, a `SmoothedFeatures` snapshot, the active
`Theme.Snapshot`, and a shared magnitudes `MTLBuffer`. The mapping
below is what each shader actually *reads* — features are wired the
same way across all modes for consistency.

### Aurora (`Aurora.metal`)

| Feature        | Used as                                                                |
| -------------- | ---------------------------------------------------------------------- |
| `lowBand`      | Vertex Y displacement gain (`0.55 + 0.7·lowBand·5.5`)                   |
| `midBand`      | Ripple amplitude in vertex shader                                       |
| `highBand`     | Sparkle accent intensity along ribbon crest                             |
| `beat`         | Emissive envelope kick + per-ribbon displacement scale                  |
| `loudness`     | Fragment intensity boost                                                 |
| `level`        | Vertex shader passthrough (currently unused; reserved for future motion) |
| Palette        | Primary→secondary→accent along ribbon length (sweep + sin time bias)    |
| `ribbonIndex`  | Per-ribbon phase offset (3 layered ribbons)                              |

### Bloom (`Bloom.metal`)

| Feature      | Used as                                              |
| ------------ | ---------------------------------------------------- |
| `lowBand`    | Blob base radius (`0.055 + 0.04·lowKick`)            |
| `midBand`    | Smin merge radius, inner-colour mix toward accent    |
| `beat`       | Shockwave radius `0.65·beat`, ring intensity         |
| `magnitudes` | Per-blob radius perturbation (12 blobs, stride 5)    |
| Palette      | primary (outer), secondary↔accent (inner), accent (shock) |

### Lattice (`Lattice.metal`)

| Feature      | Used as                                          |
| ------------ | ------------------------------------------------ |
| `magnitudes` | Per-instance height via diagonal index mapping   |
| `loudness`   | Universal height bump + emissive offset          |
| `beat`       | Extra height add on onset                        |
| Palette      | primary→accent along height; secondary as hue bias |

### Filament (`Filament.metal`)

| Feature   | Used as                                                                  |
| --------- | ------------------------------------------------------------------------ |
| `highBand`| `flowStrength = 0.45 + 6.0·high` driving the curl-noise field amplitude  |
| `lowBand` | Vertical sway envelope on each particle                                  |
| `beat`    | Radial thrust (`0.12·beat·lifeT`) + colour brightness boost              |
| `loudness`| Per-particle alpha gain                                                  |
| Palette   | Per-particle sweep primary→secondary→accent                              |

### Halo (`Halo.metal`)

| Feature   | Used as                                                            |
| --------- | ------------------------------------------------------------------ |
| `loudness`| Ring radius + thickness                                            |
| `midBand` | Superellipse angular warp amplitude                                |
| `beat`    | Radius push (subtle, +0.04 max)                                    |
| `highBand`| Inner sparkles                                                     |
| `lowBand` | Background wash intensity at the bottom                            |
| Palette   | accent+primary (ring), primary (inner), secondary (outer aura)     |

---

## Renderer architecture

```
MTKView ──delegate──> Renderer (MainActor)
                         │
                         ├─ AudioCaptureController.features      (snapshot per draw)
                         ├─ Theme.snapshot                       (palette uniforms)
                         ├─ AppState.activeMode                  (which mode draws)
                         ├─ magnitudesBuffer                     (64 floats, shared)
                         │
                         └─ modes[VisualizerID] : any VisualizerMode
                              ├─ AuroraVisualizer    (3201 verts × 3 ribbons)
                              ├─ BloomVisualizer     (fullscreen triangle)
                              ├─ LatticeVisualizer   (unit cube × 484 instances)
                              ├─ FilamentVisualizer  (80k point sprites, no buffer)
                              └─ HaloVisualizer      (fullscreen triangle)
```

Each draw call:

1. `Renderer.drawOnMain` builds the per-frame `VisualizerFrame`.
2. The render-pass descriptor is cleared to `palette.background`.
3. The active mode's `encode(into:frame:)` runs — Bloom / Lattice /
   Filament / Aurora invoke the shared `BackgroundPass` first so the
   palette gradient sits underneath their foreground; Halo manages its
   own background so it can stay editorial.
4. Encoder ends, drawable presents, command buffer commits.

No depth buffer is used. Lattice declares an always-pass depth state
explicitly so MTKView's default depth attachment doesn't cull back
faces.

---

## Smoothing strategy summary

The whole point of the attack/release filter is that audio features
are noisy at 47 Hz and shaders need stability. Two design rules:

- **Attack ≫ release** so the eye sees onsets but not noise.
- **Beat envelope decays in the detector, not in the renderer**, so
  the shader can read `beat` ∈ [0, 1] and trust it.

If you wire a new feature into a shader, route it through
`AudioCaptureController.smoothed*` first unless you specifically want
sample-level jitter.

---

## File map

```
Auralis/
├── App/                            SwiftUI shell, menu bar, app state
├── Audio/                          SCStream + vDSP + onset
├── NowPlaying/                     Music.app distributed notification
│                                   + iTunes Search API + k-means
├── Render/
│   ├── Visualizer.swift            VisualizerMode protocol + factory
│   ├── MatrixMath.swift            column-major matrix helpers
│   ├── BackgroundPass.swift        palette gradient fullscreen pass
│   ├── OffscreenRenderer.swift     headless render for tests + tool
│   ├── Renderer.swift              MainActor coordinator / dispatcher
│   ├── MetalView.swift             NSViewRepresentable bridge
│   ├── Modes/
│   │   ├── Aurora/                 ribbon mesh
│   │   ├── Bloom/                  SDF metaballs
│   │   ├── Lattice/                instanced grid
│   │   ├── Filament/               point-sprite particles
│   │   └── Halo/                   editorial torus
│   └── Shaders/*.metal             all visualizer + background shaders
├── UI/                             SwiftUI views + Theme bridge
├── Tools/PreviewRenderer.swift     --render-previews CLI mode
└── Resources/                      Info.plist, entitlements
```
