# Fixed-step authored camera tracks

Godauldron can author and replay camera paths against the experiment's **absolute integer fixed-step timeline**, without controlling or simulating a provider's runtime state.

## Authoring and playback

Select the scene's camera, enter a **Camera track** name, and move/seek the **unmeasured** playback timeline. Position the camera using Orbit/Fly/bookmarks, then choose **Key at step**. Repeat at a different step; two or more distinct keys are required. **Save** persists the track to `user://camera_tracks/tracks.json`. The picker loads an existing named track, **Follow** enables/disables camera path evaluation, and **Delete track** deletes the selected stored track. Tracks are matched by **experiment manifest ID, scene-relative camera path, and track name**, not by list index. No provider assets or scripts are rewritten.

Camera paths are evaluated by step index, not elapsed wall-clock time or frame presentation cadence. Position, orbit target, lens and shift scalars interpolate linearly; rotation uses **shortest-arc quaternion spherical interpolation** to preserve orthonormal orientation across ±180-degree turns. Projection, aspect convention, and culling mask are held as discrete camera state, switching at the authored key. Crossing projection conventions also holds the left camera's optical values until the discrete switch. Before the first key and after the last, the endpoint is held. Both the camera snapshot and its per-key step values are strictly validated.

The stored document uses versioned, bounded JSON: up to 40 named tracks, 64 keys each, integer steps from 0 through 12,000. Invalid/future-schema files cannot be silently overwritten by a save, and writes go through an atomic staging file. Camera paths cannot escape the selected experiment scene.

## Frame sequences and measurement isolation

If **Follow** is active when **Export PNG frames** begins, the exporter:

1. Captures the complete authored camera track in the sequence-level provenance.
2. Resets/seeks the provider's own existing fixed-step playback to the requested start.
3. Applies the camera state **after provider setup/seek**, to the selected scene camera.
4. Applies the track at every subsequent absolute step **before** awaiting each rendered frame.
5. Stores frame-step camera-track identity alongside the rendered camera pose and graphics metadata in every PNG sidecar.

There is no interpolation based on wall-clock deltas in a capture. PNG numbering, provider steps, camera key evaluation and manifest step numbers all share one fixed-step index. Capturing is explicitly **unmeasured** and runs outside performance baselines. The selected track cannot be edited or changed while capture is in progress; if its scene camera goes missing, export fails rather than switching silently to a different camera.

Tracks are also applied to interactive playback after step/seek/reset. **They are not applied to measured benchmark callbacks or campaigns**, which retain their provider-owned camera and original timing boundaries. A track does not constitute a simulation/solver checkpoint. Provider/HW nondeterminism still affects scene appearance even when the viewport pose is deterministic.

## Validation and remaining scope

Unit/host tests check quaternion shortest path, interpolation, persistence, real camera-key authoring, and benchmark isolation on both Godot tracks. The graphical sequence test checks actual rendered camera positions and per-frame JSON for several absolute steps. Future capabilities include independent camera easing/curve editors, multi-camera compositing and simultaneous comparisons, explicit per-provider camera events, non-PNG output, and HDR/EXR image transport.
