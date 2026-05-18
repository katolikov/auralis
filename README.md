# Auralis

A modern macOS visualizer for Apple Music. Renders Metal-powered
generative visuals driven by system audio captured directly from
the Music app — no third-party audio drivers required.

> **Status:** Milestone 1 — skeleton app, Metal pipeline,
> ScreenCaptureKit audio capture filtered to `com.apple.Music`,
> single broadband level meter.

## Requirements

- macOS 14 Sonoma (15+ recommended)
- Xcode 16
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & run

```bash
make run
```

The first invocation generates `Auralis.xcodeproj` from `project.yml`,
then builds Debug and launches the bundle.

Other targets:

```bash
make build      # build only
make archive    # release archive at build/Auralis.xcarchive
make open       # open the regenerated Xcode project
make clean      # remove derived data + regen the project
```

## First-launch permissions

1. **Screen Recording** — granted in System Settings → Privacy &
   Security → Screen Recording. Apple's ScreenCaptureKit reuses this
   permission gate even for audio-only capture. After granting,
   relaunch Auralis (TCC caches per-process).
2. **Music must be running.** Auralis filters SCK capture to the
   Music app's bundle ID (`com.apple.Music`). No other windows or
   audio sources are captured.

The status chip in the top-left of the window reflects capture state
and surfaces actionable error messages.

## Signing

The project ships with ad-hoc signing for local development
(`CODE_SIGN_IDENTITY: "-"`). For distribution, set your Developer Team
in `project.yml` and regenerate. Hardened runtime is enabled.

## Architecture (so far)

```
ScreenCaptureKit (Music.app, audio-only)
   → CMSampleBuffer (Float32 stereo @ 48 kHz)
   → AudioMath.rms (vDSP_measqv per channel, mean & sqrt)
   → AudioFeatures { level } via AsyncStream
   → AudioCaptureController (@MainActor, attack/release smoothed)
   → MetalView → Renderer.draw → Background.metal
                                   ↑ uniforms: time, level, aspect
```

The Metal pipeline runs a single fullscreen-triangle pass and a
shader that establishes the visual register for later milestones —
deep cool gradient, soft halo, level-responsive radial bloom.

## Roadmap

| Milestone | Scope                                                        |
|-----------|--------------------------------------------------------------|
| 1 ✅      | Skeleton + Metal triangle + SCK audio level                  |
| 2         | vDSP FFT, band energies, onset detection, debug HUD (⌘D)     |
| 3         | MusicKit now-playing, artwork palette, overlay UI            |
| 4         | Aurora visualizer end-to-end                                 |
| 5         | Bloom / Lattice / Filament / Halo + mode switcher (⌘1–⌘5)    |
| 6         | Fullscreen, menu bar item, onboarding sheet                  |
| 7         | Snapshot tests, DESIGN.md, archive build                     |

## Layout

```
Auralis/
├── App/             SwiftUI @main + window styling
├── Audio/           SCK capture, vDSP RMS, MainActor controller
├── Render/          MTKView bridge, renderer, .metal shaders
├── UI/              SwiftUI views (status chip, level bar)
└── Resources/       Info.plist, entitlements
```
