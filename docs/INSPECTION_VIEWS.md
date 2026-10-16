# Scene camera views and rendered pixel inspection

The **Scene camera** chooser lists every `Camera3D` under the selected experiment scene, including cameras nested in imported or provider-authored rigs. Choosing a camera sets it as the active viewport camera and binds the ordinary orbit, pan, dolly, frame and reset controls to that camera. No special camera naming or provider hook is required.

Use **View name → Save view** to persist the current camera position, rotation basis, projection, horizontal/vertical aspect convention, lens parameters, near/far planes and orbit target. A view is keyed to the experiment manifest ID and the camera's scene-relative node path. **Restore view** returns the camera and orbit state; **Delete view** removes the saved entry. Reusing the same name and camera path updates that view. Stored views survive application restart in `user://inspection_views/bookmarks.json` and are validated before use. Missing scene camera paths produce a visible error rather than silently substituting another camera. Captured PNGs, frame sequences and pixel readbacks include the selected scene camera path alongside experiment identity, so different authored viewpoints are distinguishable in evidence.

These are editor-style camera positions, **not** simulations or playback checkpoints. Saving and restoring is disabled during measured runs and image capture. Camera choices and view snapshots are separate from source scene assets and never serialized as executable scripts. A provider that destroys/replaces a camera node must reselect or restore the view after rebuilding the scene. Configuration-session camera snapshots continue to work independently.

## Rendered pixel magnifier

Enable **Inspect pixel**, then left-click the experiment viewport. The host pauses unmeasured playback, awaits the next completed rendered frame, and reads the viewport texture **once**. The detail strip shows the exact pixel coordinates and final RGBA8 values, plus a 13×13 texel region enlarged with nearest-neighbor sampling. The magnified strip lives outside the experiment's viewport and is not included in screenshots/PNG sequences.

Coordinates are mapped from the `SubViewportContainer`'s local display coordinates to the actual captured image dimensions. Out-of-bounds clicks are rejected. The pixel value is the final displayed output **after rendering/postprocessing and RGBA8 conversion**, not HDR linear radiance, material albedo, object identity, or a GPU duration.

Readback is excluded from measured benchmarks: clicking the magnifier during an active run is rejected, and readback reserves the same capture lifecycle that prevents starting a benchmark until completion. There is no continuously polling pixel sampler or hidden device readback.

## Remaining inspection work

Free-fly camera movement, multiple viewport comparisons, persistent named camera-path integration with session configurations, wireframe/normal/depth diagnostic passes and richer native render-debug controls remain separate capabilities. The scene-owned default camera is still authoritative until the user explicitly selects another.
