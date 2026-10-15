# Tracking upstream Godot

## Target and compatibility

Godauldron develops against upstream godotengine/godot master. CI tests both the newest published Godot release across major versions (edge track) and the newest published Godot 4 release (compatibility track). There is no permanent major or minor release pin. As of 2026-10-15, the latest confirmed public development snapshot is 4.8-dev7 and upstream master has begun its 4.8 beta transition.

The CI preview helper queries GitHub releases dynamically at run time. Its default follows the newest major; `--major 4` limits selection to the Godot 4 compatibility track. Keeping both tests preserves the bleeding-edge target without abruptly discarding compatibility coverage. A manual workflow fetches a requested upstream ref (default master), compiles Linux and Windows editors with SCons, smoke-tests the project and uploads short-lived build artifacts. The manual workflow is an opt-in source build; it does not silently distribute experimental engines. The Windows and Linux source-build jobs are configured but have not yet been executed successfully on CI.

## What the smoke test means

The rolling preview CI job verifies project import, script/scene loading, and a short process run. Headless Godot does not provide equivalent GPU rendering capabilities; passing the smoke does not establish rendering correctness, GPU feature support or real hardware performance.

Native GPU testing needs separate graphical runners and representative hardware, including both Vulkan and Direct3D 12 where relevant.

## Custom builds and binary distribution

Stock upstream comes first. If an integration is blocked by a verified engine gap, use the smallest possible downstream patch, track upstream discussion, and build compatible editor/export templates and GDExtension libraries together. An engine build, its extension interface and its native extension binaries form a compatibility set. Do not mix unrelated prerelease builds and extension binaries without validation.

Distribution of patched builds requires platform testing, original licensing notices, and a precise explanation of supported features. Public release automation should only be enabled after this compatibility and distribution workflow has been demonstrated.

## Upstream proposal checklist

- Reproduce the deficiency in current upstream master without a specific hobby-project dependency.
- Exhaust the relevant RenderingDevice, RenderingServer, CompositorEffect and GDExtension interfaces.
- Propose generalizable behavior with precise ownership, synchronization and error semantics.
- Include performance measurements, tests and at least one more use case than the motivating technology where possible.
- Keep temporary Godauldron workarounds in adapters rather than altering the universal experiment contract.

## Local development

Use a current official Godot preview, or compile upstream Godot master using its documented build instructions. The GitHub Actions source-build workflow also produces a Linux editor artifact. Updating to the latest engine is an explicit, testable operation rather than an irreversible project migration.
