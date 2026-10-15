# Potential Godot upstream improvements

This register identifies **investigation candidates**, not established missing engine features. Each must be checked against current master and supported with a minimal reproducer before proposing new APIs.

| Priority | Investigation | Required evidence |
| --- | --- | --- |
| P0 | Cross-queue and external GPU synchronization | Determine whether current public interfaces can order SDK-produced buffers/images before engine consumption without global stalls; demonstrate an actual gap |
| P0 | Safe native buffer/image sharing and ownership | Test existing RenderingDevice handles, flags and lifetimes on Vulkan and D3D12; document unsafe or unavailable operations |
| P0 | Compute-to-render geometry access | Verify existing mesh buffer exposure and render consumption paths, including buffer usage and barriers |
| P1 | GPU feature and extension negotiation | Test whether required optional Vulkan/D3D12 features can be requested or detected before the engine creates a device |
| P1 | Arbitrary rendering/compute pass integration | Audit CompositorEffect and existing render-stage hooks against concrete requirements; avoid proposing an entirely new renderer |
| P1 | Timestamp, memory and barrier diagnostics | Establish what Godot already instruments and expose only demonstrably absent capabilities |
| P2 | Frame generation, latency and swapchain integration | Verify presentation ownership requirements and backend limitations distinct from regular post-processing |
| P2 | External memory import/export | Identify specific supported sharing scenarios, cross-device constraints and complete synchronization rules |
| P2 | Cross-platform backend parity | Reproduce shortcomings on relevant Vulkan, D3D12, Metal or other supported drivers |

## Confirmed starting points

- RenderingDevice.get_driver_resource supplies native driver-resource handles. Handle visibility does not automatically provide command-buffer submission safety, synchronization, resource ownership or device feature negotiation.
- Godot PR [#118973](https://github.com/godotengine/godot/pull/118973), merged on 2026-06-19, exposes mesh surface RenderingDevice buffer RIDs to GDExtension. Verify its practical behavior on master before proposing equivalent functionality.
- The M0 harness does not presently require downstream Godot changes.

## Preparing an upstream proposal

Include a stock-master reproducer, expected/actual behavior, affected APIs and backends, tests, CPU/GPU trace evidence when applicable, a technology-neutral proposal, resource lifetime and synchronization semantics, and an estimate of maintenance burden.

Avoid upstreaming a convenient shortcut if an existing Godot abstraction already solves the real problem.
