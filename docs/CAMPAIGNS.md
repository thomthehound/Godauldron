# Experiment campaigns

A campaign is a versioned, technology-neutral JSON file stored under `campaigns/`. It defines a reusable parameter preset, one sweep axis, a baseline, and a bounded set of repeated runs.

## Example format

```json
{
  "schema_version": 1,
  "id": "org.godauldron.reference.grid-sweep",
  "experiment_id": "org.godauldron.reference",
  "base_parameters": {"amplitude": 0.65, "speed": 1.0},
  "axis": {"parameter": "grid", "values": [4, 8, 12]},
  "baseline_index": 1,
  "repetitions": 2,
  "warmup_steps": 3,
  "sample_steps": 12
}
```

The experiment ID must match a loaded manifest. The `base_parameters` dictionary overrides manifest defaults, and each axis value overrides the selected parameter. The axis ordering is preserved. `baseline_index` is zero-based; 1 selects grid size 8 in this example.

The schema accepts integral JSON numbers for integer fields (Godot parses JSON numbers as floats), but rejects fractional values and booleans where integers are required. Parameter types and bounds are taken from the experiment manifest.

To keep accidental expensive campaigns bounded, there can be at most 32 axis values, 128 runs overall, and one million steps in each phase. Repetitions must be positive. A namespaced, filesystem-safe lowercase campaign ID is required.

## Running and saving

Choose an experiment in the host, select a compatible campaign from the dropdown, and click **Run campaign**. All cases run sequentially using the same `ExperimentRun` lifecycle: scene setup, optional warmup, the sampling-boundary callback and measured steps.

Each repetition saves a normal report to `user://results`. After completion or cancellation, a separate `campaign_*.json` summary records the ordered axis, baseline index, per-case repetition counts, paths to individual result reports, and descriptive CPU callback-time comparisons.

Stopping a run, switching experiments or starting an ordinary run cancels its campaign. The interrupted repetition and incomplete summary are retained; missing cases are never marked completed. A failed result write aborts the sequence.

## What comparisons mean

The case mean averages each completed repetition's **host-step CPU wall-time mean**. The `relative_to_baseline` ratio divides that case mean by the baseline mean. Ratios are calculated only when both the case and baseline have their full repetition counts and baseline time is positive.

A ratio of 1.25 means the host callback took 25% more CPU wall time, on that system, than the designated baseline. It says nothing about GPU execution time or statistical significance. Increasing reference geometry grid size changes workload and is not a same-work comparison between implementations.

Credible GPU performance tests will also need hardware and driver metadata, comparable workloads, synchronization with actual GPU completion, and adequate sampling and variability analysis. Arbitrary results from different machines cannot be used interchangeably.

## Descriptive statistics and optional engineering guard

Each case includes mean, median, minimum, maximum, population standard deviation and coefficient of variation across completed repetition-level host callback CPU means. Missing values stay null. The host displays a comparison table; JSON remains the exportable authoritative result.

By default, campaigns have no regression verdict. Authors comparing genuinely equivalent workloads may opt into an engineering limit:

```json
"regression_guard": {
  "max_ratio": 1.1,
  "min_repetitions": 5,
  "max_coefficient_of_variation": 0.15
}
```

A nonbaseline case is `within_limit` or `over_limit` only when it and its baseline completed all requested repetitions, each has enough independent runs, the baseline mean is positive, and both satisfy the configured coefficient-of-variation limit. Otherwise status is `insufficient_data`, `unavailable`, or `unstable`. The baseline reports `baseline`. Without a configured guard, other cases report `not_configured`.

This is a descriptive *engineering observation*, not a statistical confidence interval, hypothesis test, CI build failure or proof of a performance regression. The reference grid campaign intentionally contains no limit because its cases represent different workloads.
