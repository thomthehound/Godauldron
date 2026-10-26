# Authored Environment and camera-only exposure inspection

Godot's `Environment` resource is the actual lighting/tonemap/postprocess configuration used by `WorldEnvironment` or a higher-priority `Camera3D.environment`. Godauldron can now inspect these effective camera/scene values and optionally preview photographic changes **without modifying any provider-owned Environment resource**.

## Inspection grading

Open **Graphics → Advanced…**, enable **Host inspection grading**, and set:

- **Exposure offset (EV)**: -4 to +4 stops relative to the authored environment's tonemap exposure. +1 EV multiplies that value by two, -1 divides it by two.
- **Post-tonemap contrast**: 0.5–1.5; **saturation**: 0–2.0.
- Disabling the toggle immediately restores the camera's original `Environment` reference.

The host resolves the active scene-owned camera's actual `Environment` resource: a camera-authored override takes priority, followed by the scene's `WorldEnvironment`, then an inherited viewport world environment. **If no valid environment exists, grading fails explicitly** instead of creating an unrelated default scene. The host creates a deep duplicate of the resolved resource, attaches the duplicate to the selected camera and applies changes only to the duplicate. This preserves authored sky, lighting, postprocessing and resource ownership. Updating the values recomputes exposure from the original source, not cumulatively from the previous preview value.

If the camera or experiment changes, the host releases the old override and restores the original camera Environment reference only if it still owns the override. If a provider replaces the camera Environment while grading is active, the host does not overwrite that new provider resource.

The controls are intentionally **inspection/capture-only** for now. Godauldron refuses to begin a benchmark or campaign while grading is enabled. This protects measured performance and ensures that host-only visual diagnostics cannot silently become a benchmark baseline.

## Effective provenance and captures

PNG still captures, fixed-step frame sequence summaries and individual frame sidecars record the **actual effective Godot Environment values**, including tonemapping, pre-tonemap exposure factor, post-tonemap grading, background and ambient light energy, and several postprocessing enabled flags. The record identifies the source (camera, scene WorldEnvironment or viewport world) and whether an opt-in host clone is active. Benchmark reports record the scene's actual Environment with the host grading disabled.

For fixed-step capture, a provider may rebuild its environment during setup. The host releases its previous clone before setup and reapplies the chosen grading **after** the provider's reset/seek and any authored camera-track binding, then records the effective properties of each captured render. If rebinding is impossible, the sequence is incomplete with a concrete error rather than attributing the prior environment to new frames.

An exposure offset is not the same as a raw sensor exposure, calibrated HDR transfer function or a true HDR framebuffer. **PNG viewport readbacks remain display-referred**; their brighter appearance is not evidence of preserved linear HDR radiance. No raw HDR/EXR export is claimed until a supported renderer/device readback actually supplies an HDR pixel format. The renderer-dependent final image (and provider shaders) remains authoritative.

## Remaining Cauldron-style controls

Environment-specific GI/reflections/glow capabilities, stable scene lighting presets, physical CameraAttributes exposure, per-renderer feature negotiation, native HDR intermediate capture, EXR export and hardware-calibrated output displays remain future gates. Godauldron should never approximate these by modifying providers' materials or labeling tonemapped PNG bytes as linear HDR.
