# Saved configurations and Cauldron-class acceptance

## Implemented in this slice

The experiment catalog can be filtered by name, category, manifest ID or description. Filtering changes only the visible list; it does not unload the experiment or cancel measurement. Visible indices translate back to stable manifest identities.

A named configuration is written under Godot's `user://sessions` as versioned JSON. Save/Load includes the experiment manifest ID, parameter values (including currently selected glTF/scene choice), host graphics profile and requested per-viewport settings, warmup/measurement step counts, fixed interactive playback delta, inspection grid/bounds and camera position/orientation/projection/FOV/size. A capture of effective graphics settings is included as provenance; **host intent** is what gets restored, subject to experiment-owned overrides.

Load validates manifest identity, exact parameter types/allowed choices/ranges, numeric finiteness, graphics keys/profile, step counts and camera/inspection data before interrupting a working run. It preflights declared native extensions before changing a scene. A valid restore first saves/cancels any prior measurement, applies all fields coherently, and updates camera inspection without pretending the graphics or solver are identical on another machine.

**Not an execution checkpoint:** serialized configurations do not contain hidden solver state, GPU buffers, timeline position, native libraries or runtime allocations. Session loading resets the experiment through its normal preview/setup path. Native provider settings outside the manifest, authored scene lighting/exposure, output resolution and exact engine/driver state are *not* restored yet. To reproduce a particular visual baseline, compare the session provenance and capture sidecars, and explicitly control those remaining environmental factors.

Existing manifests and custom provider scenes remain unchanged. A new session file cannot overwrite an existing filename; saving multiple configurations with identical display names creates separate files.

## Next Cauldron-class gates

**1. Performance observability (P0).** Initial rolling host process intervals, orchestration remainder, callback distributions, percentiles, and run-export metadata are implemented. Optional completed device-sourced provider reports are validated and labeled provider-declared, never inferred from host timings. Remaining: real native synchronization validation, full engine-thread/render timelines, CPU/GPU correlation and hardware baseline methodology. See [Performance observability](PERFORMANCE_OBSERVABILITY.md).

**2. Camera and visual inspection (P1).** Camera selector and saved bookmarks, free-fly controls, pixel-coordinate zoom/magnifier, meaningful nonintrusive debug overlays. Acceptance: the same subject may be inspected from two named cameras and restored exactly; debug costs are visible/opt-in rather than included silently in production performance.

**3. Full graphics workstation (P1).** Expand Low/Medium/High/Ultra/Showcase with per-renderer controls for exposure, environment, lighting, GI, reflections, filtering, HDR/output resolution and postprocessing. Discover which settings are actually supported and whether a change requires reload/restart, and allow provider ownership. Acceptance: restoring a saved visual-regression preset reproduces every supported graphics setting; unsupported entries are explicit instead of ignored.

**4. Animation/capture sessions (P1).** Bounded frame-accurate numbered PNG export from fixed-step playback and per-frame/sequence metadata is implemented. EXR, camera tracks, animated comparisons and video export are pending. Acceptance: a repeated fixed-step request labels each recorded frame with the same timeline step/time; numerical and visual determinism remains subject to provider and hardware behavior. See [Frame sequences](FRAME_SEQUENCES.md).

**5. Independent native integration (P1→P2).** Try the real LoxFX GDExtension/groom and eventually another unrelated producer. Keep engine-owned, provider-owned and shared resource policies explicit, with separately attributed CPU, GPU, copy/upload, render and synchronization costs. Acceptance: third party can install and demonstrate a native experiment without editing host code; diagnostic CPU upload is never labeled production GPU performance.

**6. Portability and authoring (P2).** Controlled session export/import (without arbitrary file execution), stable preset identifiers and migration rules, editor-authored custom scene templates and provider-contributed diagnostic panels/parameter types. Acceptance: a colleague can load the same supported configuration and receive actionable explanations about unavailable resources/parameters rather than unexplained silent substitutions.

This ordering emphasizes reusable workflows and correct measurement boundaries rather than duplicating Cauldron's rendering implementation inside Godot.
