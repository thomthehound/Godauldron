# Fixed-step PNG frame sequences

Godauldron can export a numbered PNG sequence from any experiment that implements `godauldron_step(fixed_dt)` and can reset through `godauldron_setup(parameters)` or `godauldron_preview(parameters)`.

In **Interactive playback (NOT measured)**, choose **From step** (zero-based) and **Frames** (1–240), then select **Export PNG frames**. Frames are captured at the playback control's fixed Δt, beginning with the requested step. The exporter resets/rewinds through the experiment's supported playback contract and leaves interactive playback paused at the last exported frame.

Results are saved to `user://sequences/sequence_<date>_p<process>_<number>/`. Each sequence contains:

- `frame_000000.png`, `frame_000001.png`, …: Godot viewport frames
- Matching `frame_XXXXXX.json` sidecars: experiment identity, parameters, graphics settings, capture-state hook output, timestep and timeline step/time, and camera context
- `sequence.json`: requested range, written frames, complete/incomplete status, and indexed frame list

A partial export is marked **incomplete**, never silently represented as a full sequence. The manifest is updated after each successfully written frame, so interrupted exports retain the last committed frame index; staged writes preserve the previous valid manifest during replacement. Previously exported directories cannot be overwritten. Benchmark and campaign execution cannot overlap export; frame readbacks are not included in measured timing. The exporter enforces an explicit frame-count bound to limit accidental long-running jobs.

The sequence manifest records the effective graphics configuration after experiment setup and host ownership reconciliation. Each frame sidecar independently records effective graphics settings at capture time, including provider-driven changes during stepping.

Frame timestamps are **fixed-step timeline values**, not elapsed GPU presentation time. Seek may be analytic if the experiment implements `godauldron_seek(seconds)`; otherwise the host uses its bounded reset-and-replay path. Repeated timestamps and parameters do **not** guarantee identical asynchronous native solver results: the provider must supply its own reproducibility contract. This is PNG-only, not an EXR/video encoder or a GPU-timer implementation.

For tests, `tests/frame_sequence_smoke.gd` verifies ordering, JSON provenance, path safety and partial exports; `tests/frame_sequence_graphics_smoke.gd` drives the production UI exporter under a graphics-backed Godot render context.
