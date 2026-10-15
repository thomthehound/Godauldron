# Roadmap and acceptance gates

Milestones are defined by demonstrated capabilities rather than time estimates or ownership by particular SDKs.

## M0 — Host bootstrap

- [x] Running Godot project with interactive experiment selection
- [x] Manifest-based discovery, parameter controls and static validation
- [x] Fixed-step host callbacks and JSON result export
- [x] Deterministic non-native scene for harness smoke tests
- [x] Python regression tests
- [x] Rolling published-preview compatibility workflow
- [x] On-demand upstream source-build workflow
- [x] CI-verifiable real Godot import/launch and correct run-result export
- [x] Automatic assertions covering experiment lifecycle, not only scene load

Exit gate: current upstream Godot opens the lab, reference runs are exportable and CI reproduces those observations.

## M1 — Cauldron-class user experience

- [ ] Searchable/categorized experiment catalog and reusable parameter presets
- [ ] Scene loading and curated glTF technical scenes
- [ ] Camera controllers, debug overlays and common visual inspection tools
- [x] Host run phases: setup, warmup, sample, final reporting and cancellation (measured CPU callback time only)
- [ ] Automated parameter sweeps, baseline comparisons and regression thresholds (sweeps, dispersion statistics, in-app results and optional engineering guards implemented; reproducible GPU regression policy pending)
- [ ] Hardware/driver metadata, logs, screenshots, image diff and magnifier
- [ ] Independently testable host services and portable experiment schemas (runner extracted; catalog/capture pending)

Exit gate: a third party adds and compares an unrelated experiment without modifying core.

## M2 — Native extension ecosystem

- [ ] Generic GDExtension adapter example unrelated to a specific SDK
- [ ] Native extension package loading and compatibility negotiation
- [ ] Separate CPU, GPU, queue, memory and frame-timing instrumentation
- [ ] GPU capture and validation tool integrations
- [ ] Vulkan and D3D12 capability surfaces, backend selection and diagnostics
- [ ] Standalone native baseline versus Godot-integrated results

Exit gate: an independent native technology can be profiled with attributable integration overhead.

## M3 — Low-level GPU interoperability

- [ ] Engine-owned, shared-resource and SDK-owned execution modes
- [ ] Demonstrated cross-queue producer/consumer synchronization
- [ ] Zero-copy compute-driven geometry or texture paths where possible
- [ ] Native render-pipeline integration with correct frame ordering
- [ ] Lifetime, resource tracking and race validation on real hardware
- [ ] Reproducers and upstream proposals for verified engine gaps

Exit gate: native workloads preserve algorithm behavior and publish GPU outputs safely and efficiently inside real Godot frames.

## M4 — Broad research and demonstration platform

- [ ] Advanced HDR, temporal reconstruction, frame generation and latency experiments
- [ ] Large representative scenes, scripted camera paths and visual baselines
- [ ] Composite experiments running several unrelated technologies together
- [ ] Portable performance regressions on real GPUs
- [ ] Release process for optional custom Godot builds and matched extensions

Exit gate: Godauldron is a usable alternative to specialist graphics prototyping frameworks and adds meaningful integration and middleware test capabilities.

## Discipline

Do not mistake an attractive demo for correct native execution. Keep reference measurements, sync correctness, and engine integration cost independently observable throughout development.
