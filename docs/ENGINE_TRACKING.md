# Tracking upstream Godot

## Target and compatibility

Godauldron develops against upstream godotengine/godot master. CI tests both the newest published Godot release across major versions (edge track) and the newest published Godot 4 release (compatibility track). There is no permanent major or minor release pin. As of 2026-10-15, the latest confirmed public development snapshot is 4.8-dev7 and upstream master has begun its 4.8 beta transition.

The CI preview helper queries GitHub releases dynamically at run time. Its default follows the newest major; `--major 4` limits selection to the Godot 4 compatibility track. Keeping both tests preserves the bleeding-edge target without abruptly discarding compatibility coverage. Separate source-build workflows provide opt-in Linux and Windows editor artifacts from the selected upstream revision; no engine release is published automatically.

## Build master HEAD or an upstream development branch

After the workflows are merged onto Godauldron's default branch, choose **Actions → Build Godot master HEAD → Run workflow**. The defaults use `godotengine/godot` and `master`.

The [manual workflow](../.github/workflows/build-engine.yml) invokes the [reusable source builder](../.github/workflows/build-godot.yml). The reusable workflow:

- Resolves the selected Git ref **once** at the start and uses that same revision for all requested platforms.
- Accepts any accessible Godot source repository and branch or tag, including a public fork used to prepare upstream contributions.
- Builds Linux and/or Windows editors; the Windows configuration includes native D3D12 support.
- Generates `extension_api.json` and `gdextension_interface.h` from each compiled editor rather than copying potentially mismatched API files.
- Uploads editor and API artifacts with `source.txt` recording the repository, requested ref and resolved revision.
- Exposes `resolved_revision` as a reusable-workflow output and leaves Godauldron-specific smoke checks in the calling workflow.

An external GitHub Actions workflow can reuse the builder:

```yaml
jobs:
  godot:
    uses: thomthehound/Godauldron/.github/workflows/build-godot.yml@main
    with:
      godot_repository: godotengine/godot
      upstream_ref: master
      build_linux: true
      build_windows: true
```

Editor builds and their API artifacts are not export templates or official Godot releases. The manually triggered source builds have not yet been validated by a full upstream compilation on GitHub Actions.

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

Use a current official Godot preview, or compile upstream Godot master using its documented build instructions. The GitHub Actions source-build workflow produces Linux and Windows editor artifacts when both platforms are enabled. Updating to the latest engine is an explicit, testable operation rather than an irreversible project migration.
