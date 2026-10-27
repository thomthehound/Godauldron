# Cauldron coverage and differentiated Godauldron gates

This document tracks **working Godauldron workflows**, not merely features present somewhere in Godot or a native SDK. A capability is not considered complete just because an engine API exists. The major reference is AMD's [FidelityFX Cauldron framework feature list](https://gpuopen.com/fidelityfx-cauldron-framework/), [FidelityFX sample controls and command line](https://gpuopen.com/manuals/fidelityfx_sdk/getting-started/running-samples/) and [FidelityFX SDK sample architecture](https://gpuopen.com/manuals/fidelityfx_sdk/getting-started/sdk-structure/). FidelityFX SDK generations have different render modules and backend support; do not conflate older Vulkan+DX12 Cauldron with newer DX12-only FSR sample frameworks.

## Status definitions

**Working:** a user-facing Godauldron path is implemented and regression exercised. **Engine-provided:** Godot may supply the facility; we still need to expose and validate the relevant workflow. **Partial:** a working subset exists, with specific missing gates. **Missing:** no independent acceptance proof. **Provider-owned:** deliberately not reimplemented in Godauldron; native algorithm/runtime ownership remains with the package.

| Cauldron capability | Godauldron state | Next material acceptance |
| --- | --- | --- |
| glTF 2.0 scene loading, cameras, skeletons, animation, PBR, punctual lights, shadow maps and IBL | Engine-provided; imported geometry fixture and curated stage are working; parity of specular-glossiness extensions/animation import not audited | Real representative animated/skinned/extension asset gallery with explicit import/effective-render checks |
| Configurable forward/G-buffer, depth, normals, motion vectors, roughness | Partial: Forward+ viewport diagnostics and one-shot native-buffer samples | Per-pass ownership, full buffer identity, linearized depth and calibrated motion vectors without provider shader replacement |
| TAA, bloom, exposure, tone mapping, HDR | Partial: host TAA and reversible camera-only grading; actual scene-linear EXR capture | Inspectable effective Godot Environment/postprocessing state, renderer-specific limits and display-output provenance |
| Shader/Pipeline compilation, hot reload and caching | Partial: real Vulkan/RD setup timings, native provider shader reload with explicit GLSL compile, transactional Vulkan pipeline replacement, source/PSO failures and completed-fence retirement; explicit bind reuse and truthful cache observability | Prove equivalent native D3D12/Godot RD pipeline reload, provider shader variant metadata and explicit cache instrumentation |
| Dynamic per-effect/render-module settings | Partial: runtime provider-owned live/rebuild/restart descriptors and actual gallery light/background control, manifest parameters and experiment graphics ownership | Portable session persistence and reproducible campaign sweeps for runtime settings with ownership, units, valid range and rebuild/restart costs; no arbitrary controls |
| Benchmark mode and frame timing | Working host/campaign reproducibility, distribution reports, native GPU timestamps and resolved queue timelines; native standalone parity is partial | Matched native-vs-host baselines, renderer pass attribution and explicit GPU/CPU/memory/presentation deltas |
| Magnifier, adjustable size and position lock | Working one-shot pixel magnifier: 9/13/21 neighborhood, zoom, captured-sample pin, RGB/luma measurements; **not live GPU magnification** | Optional explicit-rate live render-path magnifier with zero full-frame CPU readback; must disable/exclude while measuring |
| Debug geometry, light frustums, wireframe | Partial: grid, bounds, wireframe, normals, overdraw and lighting-only; light-frustum rendering absent | Opt-in truthful light/frustum diagnostic with direct scene-light geometry and render-cost provenance |
| Screenshot and interactive UI | Working native viewport SDR PNG + capture metadata, scene-linear EXR, sequences, comparison/diff and camera bookmarks | Aligned/HDR image comparisons and portable automated visual regression policies |
| Fullscreen, SDR/HDR10/scRGB/FreeSync HDR display, swapchain and presentation | Missing host display-mode negotiation; Godot handles normal window/display infrastructure | Capability-gated display mode controls, verified effective swapchain/color-space and presentation latency |
| CPU/GPU framerate limiter | Missing | Explicit unmeasured limiter with CPU/GPU clock/pacing provenance; never silently enabled during baselines |
| GPU capture with PIX and RenderDoc | Missing in-app lifecycle integration | Tool discovery, bounded capture arming and evidence provenance, no claims of native capture without tool result |
| Static/dynamic buffer allocators, command rings, timestamp queries and memory heaps | Godot-managed for engine work; native SDKs remain provider-owned. Native GDExtension diagnostic exercises actual owner/timestamp/readback boundaries | Live resource/memory budget and latency accounting, external SDK native scheduling and safe cross-queue handoff |
| Multiple GPU APIs and shader-model support | Partial: real D3D12 WARP/physical AMD and software Vulkan native compute acceptance | Vulkan/D3D12 parity on hardware, provider-selected device/capability negotiation, failure evidence |
| Multi-threaded texture loading, mip generation, asynchronous compilation | Engine-provided; working independent low-priority image-analysis worker | Surface actual import/compilation progress and distinguish engine/host/resource stalls without installing a duplicate asset pipeline |
| FidelityFX SDK-specific effect modules (FSR, CAS, CACAO, SPD, SSSR, etc.) | Provider-owned; no pretend built-in equivalents | Integrate actual independent SDK/effect packages with source algorithm, quality/performance acceptance and SDK ownership intact |

## Godauldron differentiators

Saved configurations with portable import/export, isolated experiment packs, fixed-step multi-run campaigns, explicit capture-versus-benchmark exclusion, calibrated source/output metadata, real scene-linear HDR image sequences, background image analysis, host-vs-renderer-vs-provider clock attribution and cross-queue overlap guards are laboratory services that can improve on simple effect demos. These must be demonstrated on real providers before claiming performance parity.

## Prioritization

1. **No measurement interference:** every diagnostic either operates entirely off the measured path or documents and enforces its timing costs. Never silently inject a magnifier readback, limiter, overlay or screenshot into a performance baseline.
2. **Complete inspection workflows:** accurate resource and render-pass identity, GPU/display provenance and truthful quantitative readouts, not cosmetic debug labels.
3. **Provider-facing module controls:** capability-validated runtime descriptors and dynamic controls that never steal setting ownership or GPU scheduling from independently built technology.
4. **Presentation and capture parity:** real HDR display mode negotiation, capture-tool integration, calibrated baseline comparisons and video/export workflows.
5. **True native parity:** representative production assets and effects, Vulkan/D3D12 hardware testing, and standalone-vs-Godot implementation overhead.

The current status is intentionally **not** “complete Cauldron parity.” It is a testable engineering inventory. A missing gate may be delegated to Godot, supplied by an independent provider, or implemented in the laboratory only when the native integration actually calls for it.
