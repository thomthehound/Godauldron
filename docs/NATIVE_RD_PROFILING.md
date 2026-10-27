# Native RD hardware profiling

The physical AMD acceptance path executes a Godot-owned native C++23 compute workload on D3D12. It verifies the actual DXGI adapter against the live D3D12 device, checks every output pixel, and requires resolved GPU timestamps for all measured batches. These measurements are distinct from the laboratory's frame, rendering, and independent-provider profiles.

## Run and exports

From a Windows PowerShell session in the repository:

```powershell
.\scripts\run_native_rd_amd.ps1 -Warmup 10 -Samples 100 -Passes 8 -Output native_rd_amd_profile_long.json
```

The script rebuilds and installs the native RD extension, executes the device workload and validates its evidence. On success, it writes the primary JSON record, a sibling `.analysis.json` summary, and a `.csv` with every batch including warmup rows. Sample counts range from 2 to 256, warmup from 1 to 32, and dispatches per batch from 1 to 32; the native image is limited to 1,048,576 pixels. The default configuration remains 512×512, three warmups, twelve samples and eight passes.

Analyze a previous schema-1 report or a current schema-2 report independently:

```powershell
python tools/analyze_native_rd_profile.py native_rd_amd_profile_long.json --json-output native_rd_analysis.json --csv-output native_rd_batches.csv
```

Compare a new run to a captured baseline:

```powershell
python tools/analyze_native_rd_profile.py new.json --baseline baseline.json --max-p50-regression-pct 10 --max-p95-regression-pct 20
```

Positive change percentages mean slower GPU dispatch windows. A regression limit, if requested, fails with a nonzero exit status. Comparisons require equal backend, device identity, driver, shader and workload dimensions/pass count; they never compare software against physical hardware. Without those conditions, the tool reports an incompatibility rather than a regression conclusion.

## Timing boundaries and throughput

- **GPU compute window:** Godot `RenderingDevice` captured device timestamps enclosing the native dispatch list. Includes timestamp/driver marker costs. Excludes host readback, general scene rendering and presentation.
- **Host request to readback:** CPU monotonic time from the request to completed asynchronous readback. Includes host frame scheduling and GPU transfer. Never substitute this for device GPU time.
- **Host validation:** Additional CPU wall time checking pixels and first-batch adapter provenance, after the readback result is available.
- **Host request to validated:** CPU monotonic time from the request through output verification.
- **Normalized rates:** Dispatches or pixel-dispatches per second calculated from the measured *GPU marker window*, not hardware bandwidth, actual shader instruction rate, occupancy or completed-frame throughput. A pixel-dispatch is one nominal image pixel processed by one shader dispatch, including bounds-guarded workgroups.
- **Measured device-marker cadence:** When all samples expose valid same-device GPU marker bounds, the analyzer reports consecutive batch start gaps, observed device-frame gaps, elapsed first-to-last batch time, and actual dispatch/pixel-dispatch rates across that interval. These rates **include inter-batch pacing**, unlike GPU-window-normalized rates. The marker-window fraction describes only coverage by measured native work; it is not a GPU occupancy or utilization estimate.
- **Dispersion:** Mean, p50/p95/p99, population deviation, median absolute deviation, coefficient of variation, p95/p50 ratio, first/second-half medians and both low- and high-tail batch indices. The descriptive Tukey fences (Q1 − 1.5×IQR, Q3 + 1.5×IQR) are applied when there are at least eight observations, retaining original batch indices. Neither tail automatically indicates a hardware fault or an explanation for the variation.

The measured summaries exclude warmup batches; the CSV retains them for inspection. Missing software-device GPU timestamps are reported as unavailable, never inferred from host latency. Physical-device acceptance rejects any missing measured timestamp. Schema-2 records also retain timestamp start/end values, workload dispatch geometry, and one-time shader/pipeline/descriptor lifetime evidence across the full run and after release.

The current suite does **not** measure queue occupancy, asynchronous transfer duration in isolation, presentation latency, VRAM bandwidth, memory residency, power consumption or GPU frequency. Those require separately sourced instrumentation or another explicit execution boundary.
