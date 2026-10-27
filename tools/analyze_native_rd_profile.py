"""Analyze measured native RD batches without conflating device and host clocks."""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from pathlib import Path

if __package__:
    from .validate_native_rd_profile import validate
else:
    from validate_native_rd_profile import validate


def _percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = fraction * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def distribution(values: list[float], indices: list[int] | None = None) -> dict:
    if not values:
        return {"available": False, "samples": 0}
    median = _percentile(values, 0.5)
    q1, q3 = _percentile(values, 0.25), _percentile(values, 0.75)
    fence = q3 + 1.5 * (q3 - q1)
    # Tukey fences are descriptive and only used with sufficient observations.
    outliers = ([indices[i] if indices is not None else i
                 for i, value in enumerate(values) if value > fence]
                if len(values) >= 8 else [])
    mid = len(values) // 2
    return {
        "available": True,
        "samples": len(values),
        "mean_usec": statistics.fmean(values),
        "p50_usec": median,
        "p95_usec": _percentile(values, 0.95),
        "p99_usec": _percentile(values, 0.99),
        "minimum_usec": min(values),
        "maximum_usec": max(values),
        "population_stddev_usec": statistics.pstdev(values),
        "median_absolute_deviation_usec": statistics.median(abs(v - median) for v in values),
        "coefficient_of_variation": statistics.pstdev(values) / statistics.fmean(values),
        "p95_to_p50_ratio": _percentile(values, 0.95) / median,
        "upper_tukey_fence_usec": fence if len(values) >= 8 else None,
        "high_outlier_batch_indices": outliers,
        "first_half_p50_usec": _percentile(values[:mid], 0.5) if mid >= 4 else None,
        "second_half_p50_usec": _percentile(values[mid:], 0.5) if len(values) - mid >= 4 else None,
    }


def analyze(report: dict) -> dict:
    settings = report["settings"]
    validate(report, physical=settings["mode"] == "physical_amd")
    samples = [r for r in report["records"] if not r["warmup"]]
    timed = [r for r in samples if r.get("gpu_compute_window_usec") is not None]
    gpu_values = [float(r["gpu_compute_window_usec"]) for r in timed]
    pixel_dispatches = settings["width"] * settings["height"] * settings["passes"]
    gpu = distribution(gpu_values, [r["batch_index"] for r in timed])
    # Normalized counts are rates over the marker window, not bandwidth,
    # device occupancy, standalone kernel time or complete frame throughput.
    gpu["pixel_dispatches_per_second"] = (
        distribution([pixel_dispatches * 1_000_000.0 / t for t in gpu_values])
        if gpu_values else {"available": False, "samples": 0})
    gpu["dispatches_per_second"] = (
        distribution([settings["passes"] * 1_000_000.0 / t for t in gpu_values])
        if gpu_values else {"available": False, "samples": 0})
    gpu["rate_scope"] = (
        "nominal pixel-dispatch and dispatch rates over the Godot RD timestamp window; "
        "includes marker overhead, excludes host readback and scene rendering")
    result = {
        "schema_version": 1,
        "source_report_schema": report["schema_version"],
        "device": report.get("device"),
        "driver": report.get("device_driver_info"),
        "adapter_provenance": report["adapter_provenance"],
        "workload": {
            "width": settings["width"], "height": settings["height"],
            "pixels": settings["width"] * settings["height"],
            "passes": settings["passes"], "pixel_dispatches_per_batch": pixel_dispatches,
            "warmup_batches": settings["warmup"], "measured_batches": settings["samples"],
        },
        "gpu_compute_window": gpu,
        "host_request_to_readback": distribution(
            [float(r["host_request_to_readback_usec"]) for r in samples]),
        "host_validation": distribution(
            [float(r["host_validation_usec"]) for r in samples])
            if report["schema_version"] >= 2 else {"available": False, "samples": 0},
        "host_request_to_validated": distribution(
            [float(r["host_request_to_validated_usec"]) for r in samples])
            if report["schema_version"] >= 2 else {"available": False, "samples": 0},
        "resource_lifecycle": report.get("resource_lifecycle"),
        "gpu_timestamp_rejections": report["gpu_timing"].get("rejected_timestamp_pairs", 0),
    }
    return result


def compare(report: dict, baseline: dict) -> dict:
    for item in (report, baseline):
        validate(item, physical=item["settings"]["mode"] == "physical_amd")
    # Reject superficially similar measurements that cannot support an
    # attribution-safe regression conclusion.
    for key in ("backend", "device", "device_api", "device_driver_info",
                "shader", "shader_source"):
        if report.get(key) != baseline.get(key):
            raise ValueError(f"Incompatible native GPU baseline: {key}")
    for key in ("mode", "width", "height", "passes"):
        if report["settings"].get(key) != baseline["settings"].get(key):
            raise ValueError(f"Incompatible native GPU workload: {key}")
    for key in ("vendor_id", "device_id", "device_luid_matched",
                "verified_physical_amd", "verified_software"):
        if report["adapter_provenance"].get(key) != baseline["adapter_provenance"].get(key):
            raise ValueError(f"Incompatible native adapter provenance: {key}")
    if not report["gpu_timing"]["available"] or not baseline["gpu_timing"]["available"]:
        raise ValueError("Baseline comparison requires complete device GPU timestamps")
    current = analyze(report)["gpu_compute_window"]
    reference = analyze(baseline)["gpu_compute_window"]
    return {
        "comparable": True,
        "current_samples": current["samples"],
        "baseline_samples": reference["samples"],
        "gpu_p50_change_percent":
            100.0 * (current["p50_usec"] / reference["p50_usec"] - 1.0),
        "gpu_p95_change_percent":
            100.0 * (current["p95_usec"] / reference["p95_usec"] - 1.0),
        "positive_means_slower": True,
    }


def export_csv(path: Path, report: dict) -> None:
    fields = ("batch_index", "warmup", "dispatches", "correct_pixels",
              "gpu_compute_window_usec", "gpu_start_ns", "gpu_end_ns", "device_frame",
              "host_request_to_readback_usec", "host_validation_usec",
              "host_request_to_validated_usec", "pixel_dispatches_per_second")
    pixels = report["settings"]["width"] * report["settings"]["height"]
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        for record in report["records"]:
            row = {key: record.get(key) for key in fields}
            elapsed = record.get("gpu_compute_window_usec")
            row["pixel_dispatches_per_second"] = (
                pixels * record["dispatches"] * 1_000_000.0 / float(elapsed)
                if elapsed is not None else None)
            writer.writerow(row)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path,
                        help="Compare only matching hardware, driver, shader and workload")
    parser.add_argument("--max-p50-regression-pct", type=float)
    parser.add_argument("--max-p95-regression-pct", type=float)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--csv-output", type=Path)
    args = parser.parse_args()
    if (args.max_p50_regression_pct is not None or
            args.max_p95_regression_pct is not None) and args.baseline is None:
        parser.error("A regression guard requires --baseline")
    for limit in (args.max_p50_regression_pct, args.max_p95_regression_pct):
        if limit is not None and (not math.isfinite(limit) or limit < 0):
            parser.error("Regression limits must be finite and nonnegative")
    report = json.loads(args.report.read_text(encoding="utf-8"))
    result = analyze(report)
    gpu = result["gpu_compute_window"]
    host = result["host_request_to_readback"]
    print(f"Device GPU window: p50={gpu.get('p50_usec')} us; "
          f"p95={gpu.get('p95_usec')} us; samples={gpu['samples']}")
    print(f"High GPU outlier batch indices: {gpu.get('high_outlier_batch_indices', [])}")
    print(f"Host request-to-readback: p50={host['p50_usec']} us; "
          f"p95={host['p95_usec']} us; NOT GPU execution time")
    if args.baseline:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        result["comparison"] = compare(report, baseline)
        comparison = result["comparison"]
        print(f"Matching-baseline GPU p50 change: {comparison['gpu_p50_change_percent']:+.2f}%")
        print(f"Matching-baseline GPU p95 change: {comparison['gpu_p95_change_percent']:+.2f}%")
    if args.json_output:
        args.json_output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n",
                                    encoding="utf-8")
    if args.csv_output:
        export_csv(args.csv_output, report)
    if args.baseline:
        if (args.max_p50_regression_pct is not None and
                result["comparison"]["gpu_p50_change_percent"] > args.max_p50_regression_pct):
            parser.exit(1, "GPU p50 exceeded the specified regression limit\n")
        if (args.max_p95_regression_pct is not None and
                result["comparison"]["gpu_p95_change_percent"] > args.max_p95_regression_pct):
            parser.exit(1, "GPU p95 exceeded the specified regression limit\n")


if __name__ == "__main__":
    main()
