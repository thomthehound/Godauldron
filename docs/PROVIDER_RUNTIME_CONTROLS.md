# Provider-owned runtime controls

The active experiment may expose controls that are **distinct from its manifest setup parameters**. These controls address existing provider resources and algorithms. Godauldron only validates and displays the contract and routes explicit user edits; it never recreates an SDK's native task graph, allocations, shaders or command lists.

## Optional scene-root protocol

```gdscript
func godauldron_runtime_controls() -> Array[Dictionary]:
    return [
        {
            "id": "sun_energy", "label": "Sun energy",
            "type": "float", "value": 1.0,
            "min": 0.0, "max": 3.0, "step": 0.1,
            "unit": "relative", "mode": "live",
            "renderers": ["forward_plus", "mobile"]
        }
    ]

func godauldron_set_runtime_control(id: String, value: Variant) -> Dictionary:
    # Provider checks and applies the actual native/render state.
    # "rebuild" means the provider itself completes the required rebuild
    # before returning. Godauldron never impersonates that operation.
    return {"ok": true}
```

Every descriptor has `id`, `label`, `type`, `value` (actual current/effective value), and `mode`. Supported types are `bool`, `int`, `float` and `choice`. Numeric values have explicit `min`, `max`, `step` and optional `unit`. Choices have nonempty distinct string values with labels. `renderers` optionally restricts availability to `forward_plus`, `mobile` or `gl_compatibility`. An empty list means renderer-neutral. The contract is bounded to 32 settings and 32 choices per setting; duplicates, invalid types, non-finite values, out-of-range defaults and unsupported rendering-method names invalidate the provider's entire current setting set.

`mode` distinguishes:

- `live`: the provider applies the new setting synchronously to its existing runtime.
- `rebuild`: the provider performs any required resource/pipeline rebuild **itself** and returns only when the new effective state is published; the host does not guess what resources to rebuild.
- `restart`: descriptive and **read-only** during this application session. The host will not pretend to activate unsupported device-creation or startup settings.

An unsupported renderer likewise makes the setting read-only. All edits are refused during a measured run, campaign, capture or image analysis. An explicit provider `{"ok": false, "error": "..."}` rejection leaves the old control state displayed. On acceptance, the host reads the entire descriptor set again and requires the requested value to match the provider's newly reported effective value; this also permits the provider to update dependent ranges or availability. The provider may expose different descriptors after scene setup or switching render paths.

The provider supplies the setter's semantics, including fences/retirement if a rebuild touches in-flight work. Its contract cannot be used to command native GPU work from the host on an undocumented queue. Settings are not registered in an engine-wide duplicate parameter system; existing manifest setup parameters remain authoritative for repeatable resets and campaigns.

## Timing and reproducibility

The active runtime settings are read **after setup and after run finalization**, then recorded independently in each result under `provider_runtime_controls.at_setup` and `.at_finalize`. These reads are outside the measured `godauldron_step()` callbacks. They document actual observed state, not inferred manifest defaults or independently validated GPU completion.

The host never polls a provider setting every frame. Editing is an explicit untimed UI action. A measured run disables these controls; direct or programmatic UI changes are rejected while a run or campaign is active. The regular manifest parameters and portable saved session format are unchanged: **runtime-only provider settings are not yet serialized in portable sessions or swept by campaigns**. To compare particular provider settings, an experiment must also expose reproducible setup configuration through its own manifest/scene protocol.

## Acceptance

The technical-scene gallery now exercises this contract through **real scene-owned directional/omni light energy, directional shadows and the WorldEnvironment backdrop**. Neither the host nor the fixture replaces shader/lighting algorithms. `tests/provider_runtime_controls_smoke.gd` tests actual rendered-scene resource mutation, dynamic typed controls, explicit provider rejection, provider-owned rebuild, restart and renderer gating, re-read provenance, benchmark exclusion and clean scene switching. The fixture's rebuild counter tests dispatch semantics; native GPU/pipeline rebuild correctness remains the responsibility of a real native provider and future native integration tests.
