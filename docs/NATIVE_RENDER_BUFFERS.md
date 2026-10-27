# Native renderer-buffer inspection

The **Inspect buffer** control reads Godot's own 3D renderer textures. It is a one-shot diagnostic, separate from `Viewport.debug_draw`, scene material overrides and performance measurement. A scene-owned Camera3D is required.

## Sources and semantics

| Mode | Source | Stored data | Availability |
| --- | --- | --- | --- |
| Device depth | `RenderSceneBuffersRD.get_depth_texture(false)` | Resolved device depth R, replicated in RGB of RGBA32F | Forward+ / Mobile when the device exposes a sampled depth texture |
| Normal + roughness | `get_texture("forward_clustered", "normal_roughness")` | Signed decoded normal XYZ and decoded roughness alpha, RGBA32F | Forward+ only |
| Motion vectors | `get_velocity_texture(false)` | Raw signed renderer RG motion-vector components, RGBA32F | Forward+ / Mobile when the engine produces a velocity buffer |

The source texture must be a shader-sampleable 2D texture with dimensions exactly matching the internal 3D render resolution. Stereo/multiview and render dimensions above the bounded readback limit are explicitly rejected. Missing sources fail; the host does not derive values from the presented color viewport, rerender geometry or substitute made-up motion.

The normal conversion follows the Forward+ packed-normal/roughness convention: encoded XYZ maps from [0,1] to [-1,1] and is normalized; encoded alpha values above 0.5 are mirrored before dividing by 127/255. The resulting signed normal is not directly display-referred RGB. Its coordinate frame is the renderer's prepass normal representation, not an invariant across unrelated native providers.

Device depth is not linear eye distance or a calibrated metric. Godot commonly uses reverse-Z, with near and far mapped differently from a conventional forward-Z projection. The inspector does not attempt to reconstruct distance without the source camera's projection. Motion RG is the renderer's internal motion-vector representation; no pixel-per-second or world-space speed claim is made.

## Capture and ownership

The host pauses the interactive fixed-step playback, evaluates any enabled camera track at the frozen step, and temporarily attaches an inspection compositor to the active camera. Existing camera or inherited scene WorldEnvironment compositor effects are retained in order, without modifying provider resources. The original camera compositor is restored after readback, including failure cases; restoration does not override a provider that replaced the temporary compositor.

The effect runs at `EFFECT_CALLBACK_TYPE_POST_TRANSPARENT` and requests resolved depth, Forward+ normal/roughness or motion vectors according to the chosen mode. A compute shader samples exact source texels and writes an RGBA32F texture marked copy-readable. The device asynchronously reads that staging buffer after dispatch. The render callback never waits for CPU data or writes files, and an explicit frame deadline guards against stalled captures. Result buffers remain numeric float images.

The inspection window constructs a bounded RGBA8 preview **from the captured float image**. Depth preview applies a gamma curve solely for contrast; normal preview maps signed XYZ to RGB; motion preview centers zero at 0.5 with fixed gain 16 and clamps for display. Clicking samples the unchanged full-resolution float image, not its 8-bit preview. The preview cannot be used for quantitative measurement.

Capture is excluded from host benchmark, campaign and rendering-sample attribution. The host makes no claim of GPU timestamp accuracy or cross-vendor native interop.

## Verification

Headless preview tests cover loading and runtime behavior. The software-Vulkan Forward+ integration smoke uses an actual rendered mesh, scene-owned camera and inherited provider compositor, then exercises all three UI modes. It verifies exact float buffer readback, native-buffer provenance, compositor restoration, mesh-versus-background device-depth differentiation, plausible decoded normal length/roughness, and finite velocity channels. A stationary object may correctly have zero motion, so the initial smoke does not establish moving-object velocity scale or cross-renderer invariance.

Hardware AMD/Intel/NVIDIA validation, numerical velocity-motion scene references, correct camera-projection depth reconstruction, object ID buffers, multiview, readback throughput, and provider-owned native buffers are future work.
