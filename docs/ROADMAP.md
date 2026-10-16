# Roadmap and acceptance gates

Milestones are defined by demonstrated capabilities rather than time estimates or ownership by particular SDKs.

## M0 — Host bootstrap

- [x] Running Godot project with interactive experiment selection
- [x] Manifest-based discovery, parameter controls and static validation
- [x] Fixed-step host callbacks and JSON result export
- [x] Deterministic non-native scene for harness smoke tests
- [x] Python regression tests
- [x] Rolling published-preview compatibility workflow
- [x] On-demand upstream source-build workflow
- [x] CI-verifiable real Godot import/launch and correct run-result export
- [x] Automatic assertions covering experiment lifecycle, not only scene load

Exit gate: current upstream Godot opens the lab, reference runs are exportable and CI reproduces those observations.

## M1 — Cauldron-class user experience

- [ ] Searchable/categorized experiment catalog and reusable parameter presets (search by name/category/ID/description and named configuration save/restore implemented; true category grouping, sharing/import, provider-owned setting descriptors and migration pending)
- [ ] Scene loading and curated glTF technical scenes (generic project PackedScene gallery and initial glTF/material fixtures implemented; representative production scenes pending)
- [ ] Camera controllers, debug overlays and common visual inspection tools (orbit/pan/zoom/frame/reset and optional grid, axes and bounds implemented; deeper inspection and captures pending)
- [x] Host run phases: setup, warmup, sample, final reporting and cancellation (measured CPU callback time only)
- [ ] Automated parameter sweeps, baseline comparisons and regression thresholds (sweeps, dispersion statistics, in-app results and optional engineering guards implemented; reproducible GPU regression policy pending)
- [ ] Hardware/driver metadata, logs, screenshots, image diff and magnifier (PNG capture, provenance warnings, side-by-side views, background image diff/export, limited-resolution previews and magnification implemented; true pixel magnifier, image alignment and richer hardware data pending)
- [ ] Host graphics presets, advanced quality controls and showcase/video modes (runtime viewport presets, initial advanced controls and experiment ownership implemented; exhaustive engine/scene settings, render-path negotiation, offline high-quality captures and video pending)
- [ ] Independently testable host services and portable experiment schemas (runner/playback extracted, native extension preflight and optional diagnostic path metadata added; broader SDK adapters and portable package validation pending)
- [ ] Reusable project-owned showcase authoring (Godot-editable portrait and technical inspection stages, inherited project-scene example and experiment-owned attachments provided; richer optional stage gallery, camera/lighting lock presets and frame-sequence capture pending)
- [ ] Reference-head validation: visually verify imported CC0 MakeHuman scalp shape, shading, calibrated real-world scale, precise vertex-linked landmarks and actual LoxFX root mapping (optional model and provisional markers are not enough for physics/scalp acceptance).
- [ ] LoxFX first consumer integration: real native binary smoke test on supported Windows/Linux builds, real groom import, interactive head movement and frame-sequence capture (portable package preflight, provider-neutral editable portrait/inspection stages, optional CC0 MakeHuman reference head, generic translational presentation, example inherited project scene and untimed stage controls implemented; native LoxFX binaries and graphical acceptance remain pending)
- [ ] Native GPU interop capabilities, device/queue/barrier handoff and GPU-resident rendering adapter (keep adapter-neutral until production LoxFX integration supplies requirements and hardware evidence)

Exit gate: a third party adds and compares an unrelated experiment without modifying core.

## Near-term Cauldron parity gaps (recorded, not included in the session PR)

The baseline is the independently authored native experiment workflow, not an obligation to reimplement a second rendering engine. See [Session and parity acceptance](EXPERIMENT_SESSIONS.md).

- [ ] **Observable performance**: rolling per-frame CPU main-thread, callback and integration counters; GPU timers only where provider/backend supplies correctly synchronized timestamps; clear host vs provider costs, frame pacing, stable baseline and export
- [ ] **Visual inspection**: scene-owned camera chooser/bookmarks, free-fly controls, pixel-coordinate magnifier and capability-aware wireframe/debug overlays
- [ ] **Rendering workstation**: full applicable lighting/environment/GI/exposure/quality controls with ownership and runtime/reload/restart capability declarations; freeze/reproduce camera, light, exposure, render size and environment
- [ ] **Capture**: deterministic numbered-frame PNG/EXR sequences from fixed-step timelines, source sidecars and comparisons across animation; offline encode to video and explicit realtime recorder backend
- [ ] **Experiment workflow**: share/import portable session configurations, report differences when available renderers/providers/settings differ, named provider-defined custom settings and scene templates
- [ ] **Native graphics work**: actual consumer-provided adapter and GPU synchronization, resource handoff, queue/barrier ownership and GPU-resident path; do not invent a general compute API prematurely

## M2 — Native extension ecosystem

- [ ] Generic GDExtension adapter example unrelated to a specific SDK
- [ ] Native extension package loading and compatibility negotiation
- [ ] Separate CPU, GPU, queue, memory and frame-timing instrumentation
- [ ] GPU capture and validation tool integrations
- [ ] Vulkan and D3D12 capability surfaces, backend selection and diagnostics
- [ ] Standalone native baseline versus Godot-integrated results

Exit gate: an independent native technology can be profiled with attributable integration overhead.

## M3 — Low-level GPU interoperability

- [ ] Engine-owned, shared-resource and SDK-owned execution modes
- [ ] Demonstrated cross-queue producer/consumer synchronization
- [ ] Zero-copy compute-driven geometry or texture paths where possible
- [ ] Native render-pipeline integration with correct frame ordering
- [ ] Lifetime, resource tracking and race validation on real hardware
- [ ] Reproducers and upstream proposals for verified engine gaps

Exit gate: native workloads preserve algorithm behavior and publish GPU outputs safely and efficiently inside real Godot frames.

## M4 — Broad research and demonstration platform

- [ ] Advanced HDR, temporal reconstruction, frame generation and latency experiments
- [ ] Large representative scenes, scripted camera paths and visual baselines
- [ ] Composite experiments running several unrelated technologies together
- [ ] Portable performance regressions on real GPUs
- [ ] Release process for optional custom Godot builds and matched extensions

Exit gate: Godauldron is a usable alternative to specialist graphics prototyping frameworks and adds meaningful integration and middleware test capabilities.

## Discipline

Do not mistake an attractive demo for correct native execution. Keep reference measurements, sync correctness, and engine integration cost independently observable throughout development.
