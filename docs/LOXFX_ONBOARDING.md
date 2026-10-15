# LoxFX onboarding acceptance

The purpose of this milestone is to make Godauldron **ready to receive** an independently maintained native LoxFX adapter, without embedding LoxFX-specific assumptions into the host.

| Request | Implemented in this PR | Remains |
| --- | --- | --- |
| Native GDExtension experiments (P0) | Optional manifest-declared extensions/classes, preflight before scene swap, descriptive render path, portable manifest/test contract | Exercise a real LoxFX build and its external native dependencies on each platform |
| Hair presentation stage (P0) | Editable portrait stage with neutral optional head/mannequin, soft key/fill/rim lights, selectable backgrounds, fixed camera and animated/still subject attachment point. No fabricated hair | LoxFX supplies its own groom, simulation node and rendering; hardware visual review |
| Deterministic controls (P0) | Untimed Reset/Play/Pause/Step/fixed Δt/timeline seek; analytic repeatable **stage motion**, bounded fallback replay | Physics solver tolerances must be defined and verified by its provider, especially GPU parallelism |
| Image comparison (P0) | PR #8 merged; side-by-side, differences, warnings and saved provenance | Frame sequences and video (P1) |
| Graphics ownership/freeze (P1) | Pre-existing owned settings, capture metadata, viewport controls; stationary mode and explicit playback clock | Comprehensive camera/light/environment/resolution freeze profiles |
| Technical overlays (P1) | Experiment parameters and unrestricted provider-owned child nodes/overlays under the stage | LoxFX supplies guide/follower/tangent/attachment/collider/constraint visuals |
| Native GPU interop (P1 design/P2 implementation) | No invented GPU backend; native package/scene contract remains neutral | Backend capability negotiation and resource/queue/barrier adapters |

### Honest visual-path contract

Godauldron deliberately does **not** ship synthetic hair. It ships editable portrait and technical inspection **stages**. Projects attach their own content under `SubjectMotion/SubjectAnchor`, swap the neutral placeholder off if needed, or ignore the templates and supply a fully custom scene. Presentation-stage motion is analytic and reproducible, but says nothing about the determinism or throughput of a real hair solver. The `diagnostic_cpu_bridge` manifest label is available for an experiment whose **real** simulation crosses a CPU readback/Godot upload diagnostic path; the stage itself is `godot_scene`. See [Scene authoring](SCENE_AUTHORING.md).

An experiment may display native simulation results through CPU readback and Godot mesh upload in this first phase. Such a display is acceptable for visual validation but must not be conflated with fully GPU-resident production. CPU callbacks, native GPU execution, integration transfer and render frame times remain distinct.

### Validation

`tests/loxfx_onboarding_smoke.gd` exercises native extension missing-descriptor isolation, project-owned scene inheritance, editable lighting/camera/subject attachment, deterministic stage motion and seeking, stationary presentation behavior, and interactive playback not creating measured run samples. Existing comparison/graphics CI remains intact. The binary path and real presentation quality must be validated with the LoxFX build; headless CI cannot prove the attractiveness or frame pacing of a real interactive groom.
