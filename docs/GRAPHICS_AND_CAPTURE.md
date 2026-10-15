# Graphics settings and capture architecture

The laboratory must remain useful both for **comparative experiments** and for visually impressive **showcases**. Those goals overlap, but they are not the same workload. Host settings must never silently interfere with settings that an experiment is intentionally changing.

## Settings have distinct owners

- **Host viewport**: settings the lab may apply when a technology does not claim them. Currently supported at runtime: `scaling_3d_scale`, `msaa_3d`, `screen_space_aa`, `use_taa`, `use_debanding`, and `positional_shadow_atlas_size`. The Advanced panel edits these properties directly.
- **Experiment**: parameters specified in the experiment manifest and scene-specific menus; the experiment remains authoritative over its own simulation, materials, pipelines and algorithms.
- **Experiment-owned graphics**: declare `"graphics_owned_settings": ["msaa_3d"]` in its manifest, or return a `PackedStringArray` / `Array` from `godauldron_graphics_owned_settings()` on the scene root. Use `["*"]` to reserve all currently host-controlled viewport settings. The host skips claimed properties and disables those advanced inputs rather than silently fighting the experiment.
- **Capture**: consumes the resulting rendered viewport, without owning scene algorithms or automatically reconfiguring the render pipeline.

The current ownership contract covers the host's six implemented viewport controls, not every scene `Environment` property, project-wide renderer setting, import setting, display mode, or native backend knob. A future capabilities/setting descriptor interface must expose those additional categories and distinguish **runtime**, **reload-required**, **restart-required**, **renderer-specific**, and **experiment-controlled** features. Unsupported controls should never pretend to work.

## Presets and Advanced

The available starting points are **Low**, **Medium**, **High**, **Ultra**, and **Showcase**. They set combinations of render scale, MSAA, FXAA, debanding and shadow atlas size. Selecting Advanced values marks the preset **Custom**. The currently effective viewport values are visible/readable and included in reports, even when an experiment owns some fields.

Showcase deliberately requests 1.5× 3D supersampling, 8× MSAA and an 8192-pixel local shadow atlas. These can consume substantial GPU time and memory and may be capped or unsupported on some renderers/devices. Showcase is a *creative quality preference*, **not** a claim of universally optimal image quality, maximum engine quality, stable performance, or hardware compatibility. Eventually, a showcase profile should also control full scene lighting, GI, reflection methods, texture filtering, draw distance, environment effects, HDR, output resolution and temporal accumulation through capability-aware providers rather than writing arbitrary project settings.

Experiments may change graphics settings during a run when that is their explicit subject. The host records effective values after `godauldron_setup()`. Experiments that vary renderer settings **during** sampling will need additional time-indexed per-frame setting telemetry and explicit control over when samples become comparable; a start-of-run snapshot alone is not enough for that use case.

## Still images

**Capture PNG** reads the experiment's `SubViewport` after `RenderingServer.frame_post_draw`, not the application window. Providers may expose an observation-only `godauldron_capture_metadata() -> Dictionary` callback, safe before the first setup. This is deliberately separate from `godauldron_metrics()`, which is reserved for run finalization and is never called merely to take a screenshot. Captures go to `user://captures` as a PNG accompanied by a JSON sidecar with experiment ID, current parameter controls, effective viewport graphics settings and ownership, engine version, platform, camera transform and inspection-overlay flags. A failed PNG or sidecar write is not reported as successful. The host does not overwrite an existing capture filename.

GPU image readback and PNG encoding would contaminate CPU/GPU timing if performed during a benchmark. The capture control therefore cancels and saves any active run/campaign *before* capturing. It reserves the pending frame interval too: new runs, campaigns, and overlapping screenshot requests are refused until readback finishes or the capture is cancelled. A scene switch during the interval cancels the capture. A future synchronized capture service could instead tag benchmark samples as capture-affected and explicitly exclude them, but it must never silently change what is being measured.

PNG captures are SDR and do not yet constitute reliable visual baselines. The new comparison service can show paired captures, evaluate unaligned 8-bit RGB differences, flag changed metadata and export a diagnostic diff. This is not an automated similarity judgment, alignment, mask, exposure comparison or linear/HDR pixel reference. A future **EXR** path should preserve linear HDR data for faithful high-range comparisons. Image comparison must lock the camera, dimensions, scene state, color management and render settings before assigning significance to pixel changes.

## Visual comparison of saved captures

The **Compare images…** window enumerates valid PNG/JSON pairs, presents two captures and a high-contrast red/yellow RGB and blue-alpha difference image with zoom/scroll inspection, and reports channel MAE, RMSE, maximum change and pixels changed beyond an 8/255 threshold. It warns when experiment identity, parameters, camera, graphics, inspection, engine/OS or provider capture state disagree (including provider state missing on only one side). Mismatched image dimensions are rejected for pixel comparison rather than secretly resampled; both originals remain visible. Exported difference PNG/JSON pairs under `user://comparisons` retain both source metadata records, the source names and all measured difference metrics. See [Visual comparisons](VISUAL_COMPARISON.md).

These measurements are descriptive **encoded SDR pixel-channel diagnostics**, not perceptual distances, HDR correctness, validation of GPU execution or proof of a performance regression. No tolerance should be treated as universal; next steps include precise camera/color-space matching, optional masks, registered regions, HDR/EXR, user-specified comparison policies, automated visual regression and proper magnifier inspection.

## Video and high-quality showcase plans

The preferred showcase/video design has two paths, both deriving from the same capture session definition:

1. **Offline/deterministic**: scripted camera and experiment timelines, fixed simulation/frame stepping, warmup/settling, configurable output dimensions, optional supersampling/temporal accumulation, and a lossless numbered image sequence (PNG or EXR). A video encoder can then produce playback files without forcing simulation to keep real time. Godot's MovieWriter workflow may serve as one backend, but should not become a mandatory provider.
2. **Interactive/realtime**: an explicitly selected recorder backend with dropped-frame accounting, audio and synchronization policy, codec/bitrate choices, and a clear measurement-overhead warning. Video capture must not be treated as a free GPU operation.

Future UI should separate **Experiment**, **Graphics**, **Capture**, and **Analysis** panels, with editable presets/profiles per project. A future settings registry can expose every relevant renderer-specific dial while keeping each setting's applicability, units, valid range, owner and rebuild/restart cost inspectable. Do not turn a single `High` choice into a hidden authority over experimental state.

## Validation

`tests/capture_graphics_smoke.gd` tests actual viewport property updates, ownership exclusions, cancellation/report attribution, PNG serialization, metadata, unsafe filenames and overwrite protection. Headless CI **does not** prove interactive capture pixel fidelity, video synchronization, screenshot appearance or GPU performance. Those require a graphics-backed validation phase.
