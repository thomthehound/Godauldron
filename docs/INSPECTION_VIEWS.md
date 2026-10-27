# Scene camera views and rendered pixel inspection

The **Scene camera** chooser lists every `Camera3D` under the selected experiment scene, including cameras nested in imported or provider-authored rigs. Choosing a camera sets it as the active viewport camera and binds the ordinary orbit, pan, dolly, frame and reset controls to that camera. No special camera naming or provider hook is required.

Use **View name → Save view** to persist the current camera position, rotation basis, projection, horizontal/vertical aspect convention, lens parameters, near/far planes and orbit target. A view is keyed to the experiment manifest ID and the camera's scene-relative node path. **Restore view** returns the camera and orbit state; **Delete view** removes the saved entry. Reusing the same name and camera path updates that view. Stored views survive application restart in `user://inspection_views/bookmarks.json` and are validated before use. Missing scene camera paths produce a visible error rather than silently substituting another camera. Captured PNGs, frame sequences and pixel readbacks include the selected scene camera path alongside experiment identity, so different authored viewpoints are distinguishable in evidence.

These are editor-style camera positions, **not** simulations or playback checkpoints. Saving and restoring is disabled during measured runs and image capture. Camera choices and view snapshots are separate from source scene assets and never serialized as executable scripts. A provider that destroys/replaces a camera node must reselect or restore the view after rebuilding the scene. Configuration-session camera snapshots continue to work independently.

## Rendered pixel magnifier

Enable **Inspect pixel**, then left-click the experiment viewport. The host pauses unmeasured playback, awaits the next completed rendered frame, and reads the viewport texture **once**. The detail strip shows the exact pixel coordinates and final RGBA8 values, plus a selectable **9×9, 13×13 or 21×21** source-texel neighborhood enlarged using nearest-neighbor sampling. **Zoom (4–12×)** resizes the already captured tile, without reading the GPU again. **Pin sample** freezes the rendered pixel, camera identity and diagnostic provenance until explicitly unpinned. The strip lives outside the rendered viewport and is excluded from PNG/EXR captures.

The inspector computes RGB channel **minima, maxima and means**, a local encoded Rec.709 Y′ mean/range, the number of genuine sampled image texels, and the count of duplicated pixels used only for displaying a clamped border. Clamped borders do **not** bias the neighborhood statistics, including on a 1×1 or corner image. Only pixels in the selected neighborhood are decoded for analysis and texture enlargement—there is no extra full-resolution image copy or RGBA conversion. Changes to the neighborhood selector apply on the **next explicit click**, never through continuous hidden sampling.

Coordinates are mapped from the `SubViewportContainer`'s local display coordinates to actual captured image dimensions. Out-of-bounds clicks are rejected. Values represent **post-rendering SDR RGBA8** and encoded luma, not scene-linear luminance, HDR radiance, material albedo, object identity or GPU duration. This is a captured-frame inspection tool, not an automatically updated live sampling pass.

Readback is excluded from measured benchmarks: clicking the magnifier during an active run is rejected, and readback reserves the same capture lifecycle that prevents starting a benchmark until completion. Pinned and zoom-only interactions do not request a new readback. Experiments still own the rendered viewport; host magnification is outside their render graph.

## Remaining inspection work

Free-fly camera movement, multiple viewport comparisons, persistent named camera-path integration with session configurations, wireframe/normal/depth diagnostic passes and richer native render-debug controls remain separate capabilities. The scene-owned default camera is still authoritative until the user explicitly selects another.
