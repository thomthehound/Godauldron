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

## Opt-in per-PR master builds

To request an exact upstream master test for a particular Godauldron pull request:

1. Create a repository label named `ci:godot-head` under GitHub **Issues → Labels**, if necessary.
2. Apply that label to the PR. The [PR opt-in workflow](../.github/workflows/ci-godot-head.yml) listens for the **labeled** event only.
3. It invokes the reusable builder with `godotengine/godot` `master`, builds Linux and Windows from the **same resolved commit**, and runs [shared smoke tests](../.github/workflows/smoke-built-godot.yml) against the PR's merge-test code.
4. Remove and reapply the label to request **another** build after additional PR commits. Ordinary `synchronize`, `opened`, and `push` events do not trigger this expensive workflow, even if the label stays attached.

Each request runs a single build workflow with the current HEAD as resolved **at the start of that request**; it is not a continuously moving target and does not compile Godot on every PR. Re-running an old Actions run uses the previously recorded event/ref and should not be confused with requesting a fresh build against the updated PR.

Both the manual build and PR-triggered build share the same [source builder](../.github/workflows/build-godot.yml) and [host smoke tests](../.github/workflows/smoke-built-godot.yml). They keep permissions read-only and never use `pull_request_target` to execute PR code. Artifact metadata records the precise upstream revision. Linux/Windows smoke tests do not establish actual GPU behavior; that needs real hardware.

The label-driven workflow and the manual-run interface need to be merged onto the default branch before they are dependable entry points. The expensive source-build path has not yet been tested by a complete Godot compile in CI.

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
