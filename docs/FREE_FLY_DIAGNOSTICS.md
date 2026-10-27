# Free-fly and renderer diagnostics

Godauldron's scene-camera inspection offers independent **Orbit** and **Fly** navigation modes; neither injects geometry or scripts into imported/provider scenes.

In **Fly**, hold the right mouse button over the viewport and use **W/A/S/D** to move along the camera's horizontal/forward axes; **Q/E** moves down/up in world space. **Shift** raises movement speed ×4. While right mouse is held, dragging turns the camera with pitch clamped short of ±90°. The speed control sets units per second (default 3). The host normalizes diagonal movement, clamps the per-frame navigation delta, and updates the orbit focus so switching back to Orbit stays coherent. Releasing right mouse clears the input state. All motion is disabled during benchmark steps and capture/readback, and the Camera Reset and per-scene bookmarks continue to work. No source-solver state or physics is modified.

## Render view selector

The **Render view** selector uses Godot's public `Viewport.debug_draw` API. It changes the dedicated laboratory SubViewport only; it does not apply material overrides or rewrite providers' shaders.

| Rendering method | Available modes |
| --- | --- |
| Forward+ | Authored/Lit, Unshaded, Lighting-only, Overdraw, Wireframe, Normal buffer |
| Mobile | Authored/Lit, Unshaded, Lighting-only, Overdraw, Wireframe |
| GL Compatibility | Authored/Lit only, because viewport debug-mode results are not sufficiently dependable across Compatibility driver versions |

**Normal buffer is not geometric truth for every native renderer:** custom shader vertex displacement may be disabled by some debug modes and SDK-native content may use rendering paths that Godot's viewport debug draw cannot inspect. A separate **Inspect buffer** command now reads Godot's native device depth, Forward+ packed normals/roughness and motion-vector textures through the GPU compositor. It is not a `Viewport.debug_draw` mode; it exposes captured float samples in a separate window, not a live scene-material overlay. Depth is raw device depth, not linearized view distance. Debug rendering may have a different performance cost. Godauldron rejects benchmark/campaign starts until the diagnostic is returned to **Lit** and the actual viewport draw mode is disabled. It also checks the effective viewport before and after every measured callback (including the final callback); a provider switching to diagnostic rendering invalidates the run as cancelled with an explicit reason, never publishing resolved provider GPU results for the contaminated run.

Still PNG, fixed-step sequence manifest/frame sidecars, and one-shot pixel samples record `render_diagnostic` with the selected mode, current actual rendering method, and an explicit non-baseline flag. Switching experiments resets to normal authored rendering, preventing diagnostic modes from leaking between providers. The runtime renderer is detected using `RenderingServer.get_current_rendering_method()`, not inferred from preferences or the host OS.

## Validation limits

The CI compatibility renderer exercises all navigation behavior and capability rejection. The actual Forward+ debug output requires a graphics-capable Vulkan/Metal/D3D test runner; a successfully assigned `Viewport.debug_draw` property is not evidence that shader transformations, native SDK draw calls or buffers are faithfully represented. Object-ID, tangent and draw-call inspection require further backend integration. The separate native-buffer inspector is verified through a software-Vulkan Forward+ render test; discrete GPU and native extension interop remain outstanding.
