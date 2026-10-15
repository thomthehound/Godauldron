# LoxFX onboarding acceptance

The purpose of this milestone is to make Godauldron **ready to receive** an independently maintained native LoxFX adapter, without embedding LoxFX-specific assumptions into the host.

| Request | Implemented in this PR | Remains |
| --- | --- | --- |
| Native GDExtension experiments (P0) | Optional manifest-declared extensions/classes, preflight before scene swap, descriptive render path, portable manifest/test contract | Exercise a real LoxFX build and its external native dependencies on each platform |
| Hair visual reference (P0) | Procedural three-groom portrait studio, head and bust, lit hair rim, three backgrounds, motion/still and capture metadata | Use actual LoxFX groom assets and a native strand renderer; hardware visual review |
| Deterministic controls (P0) | Untimed Reset/Play/Pause/Step/fixed Δt/timeline seek; analytic seeded hair fixture, bounded fallback replay | Physics solver tolerances must be defined by its provider, especially GPU parallelism |
| Image comparison (P0) | PR #8 merged; side-by-side, differences, warnings and saved provenance | Frame sequences and video (P1) |
| Graphics ownership/freeze (P1) | Pre-existing owned settings, capture metadata, viewport controls; stationary mode and explicit playback clock | Comprehensive camera/light/environment/resolution freeze profiles |
| Technical overlays (P1) | Provider parameter controls and provider-owned guide strand overlay | LoxFX supplies follower/tangent/attachment/collider/constraint visuals |
| Native GPU interop (P1 design/P2 implementation) | No invented GPU backend; native package/scene contract remains neutral | Backend capability negotiation and resource/queue/barrier adapters |

### Honest visual-path contract

The bundled **Hair / Motion Studio** builds a deterministic CPU ribbon geometry reference. This is *not* a LoxFX physical hair solver, not the project's actual artistic grooms, and not evidence about production GPU performance. Its purpose is to validate camera, lighting, controls, geometry visibility, provenance and repeatability. The `diagnostic_cpu_bridge` manifest label makes this boundary visible in result metadata.

An experiment may display native simulation results through CPU readback and Godot mesh upload in this first phase. Such a display is acceptable for visual validation but must not be conflated with fully GPU-resident production. CPU callbacks, native GPU execution, integration transfer and render frame times remain distinct.

### Validation

`tests/loxfx_onboarding_smoke.gd` exercises native extension missing-descriptor isolation, deterministic groom generation and seeking, stationary comparison behavior, and interactive playback not creating measured run samples. Existing comparison/graphics CI remains intact. The binary path and real presentation quality must be validated with the LoxFX build; headless CI cannot prove the attractiveness or frame pacing of a real interactive groom.
