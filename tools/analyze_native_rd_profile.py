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
    low_fence = q1 - 1.5 * (q3 - q1)
    high_fence = q3 + 1.5 * (q3 - q1)
    # Preserve original batch IDs. A low tail matters when short GPU
    # windows occur amid predominantly longer measurements.
    low_outliers = ([indices[i] if indices is not None else i
                     for i, value in enumerate(values) if value < low_fence]
                    if len(values) >= 8 else [])
    high_outliers = ([indices[i] if indices is not None else i
                      for i, value in enumerate(values) if value > high_fence]
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
        "lower_tukey_fence_usec": low_fence if len(values) >= 8 else None,
        "upper_tukey_fence_usec": high_fence if len(values) >= 8 else None,
        "low_outlier_batch_indices": low_outliers,
        "high_outlier_batch_indices": high_outliers,
        "first_half_p50_usec": _percentile(values[:mid], 0.5) if mid >= 4 else None,
        "second_half_p50_usec": _percentile(values[mid:], 0.5) if len(values) - mid >= 4 else None,
    }


def rate_distribution(values: list[float], indices: list[int]) -> dict:
    measured = distribution(values, indices)
    return {
        (key.removesuffix("_usec") + "_per_second" if key.endswith("_usec") else key):
            value for key, value in measured.items()
    }



def marker_cadence(samples: list[dict], passes: int, pixel_dispatches: int) -> dict:
    """Device-clock batch cadence, not isolated GPU compute or device occupancy."""
    if len(samples) < 2 or any(
        type(record.get("gpu_start_ns")) is not int or
        type(record.get("gpu_end_ns")) is not int or
        type(record.get("device_frame")) is not int
        for record in samples
    ):
        return {"available": False, "reason": "requires_two_or_more_complete_device_marker_pairs"}

    first = samples[0]["gpu_start_ns"]
    final = samples[-1]["gpu_end_ns"]
    elapsed_ns = final - first
    start_gaps_usec = []
    frame_gaps = []
    for previous, current in zip(samples, samples[1:]):
        gap_ns = current["gpu_start_ns"] - previous["gpu_start_ns"]
        frame_gap = current["device_frame"] - previous["device_frame"]
        if gap_ns <= 0 or frame_gap < 0:
            raise ValueError("Native GPU timestamp cadence is not monotonic")
        start_gaps_usec.append(gap_ns / 1000.0)
        frame_gaps.append(frame_gap)
    if elapsed_ns <= 0:
        raise ValueError("Native GPU profiling elapsed device time is not positive")

    active_window_ns = sum(record["gpu_end_ns"] - record["gpu_start_ns"]
                           for record in samples)
    count = len(samples)
    return {
        "available": True,
        "clock_domain": "same-device captured GPU timestamp values",
        "scope": "first measured marker start through final measured marker end; includes inter-batch idle, engine frame scheduling and other GPU activity",
        "measured_elapsed_usec": elapsed_ns / 1000.0,
        "start_to_start_usec": distribution(start_gaps_usec),
        "device_frame_delta": {
            "minimum": min(frame_gaps),
            "median": statistics.median(frame_gaps),
            "maximum": max(frame_gaps),
            "all_equal": len(set(frame_gaps)) == 1,
        },
        "completed_batch_rate_per_second": count * 1e9 / elapsed_ns,
        "dispatch_rate_per_second": count * passes * 1e9 / elapsed_ns,
        "nominal_pixel_dispatch_rate_per_second": count * pixel_dispatches * 1e9 / elapsed_ns,
        "marker_window_fraction_of_observed_elapsed": active_window_ns / elapsed_ns,
        "fraction_scope": "fraction of measured interval covered by native dispatch-list marker windows; NOT total GPU utilization",
    }


def analyze(report: dict) -> dict:
    settings = report["settings"]
    validate(report, physical=settings["mode"] == "physical_amd")
    samples = [r for r in report["records"] if not r["warmup"]]
    timed = [r for r in samples if r.get("gpu_compute_window_usec") is not None]
    gpu_values = [float(r["gpu_compute_window_usec"]) for r in timed]
    resident = settings.get("resident_batches", 1)
    sample_dispatches = settings["passes"] * resident
    pixel_dispatches = settings["width"] * settings["height"] * sample_dispatches
    indices = [r["batch_index"] for r in timed]
    gpu = distribution(gpu_values, indices)
    # Normalized counts are rates over the marker window, not bandwidth,
    # device occupancy, standalone kernel time or complete frame throughput.
    gpu["pixel_dispatches_per_second"] = (
        rate_distribution([pixel_dispatches * 1_000_000.0 / t for t in gpu_values], indices)
        if gpu_values else {"available": False, "samples": 0})
    gpu["dispatches_per_second"] = (
        rate_distribution([sample_dispatches * 1_000_000.0 / t for t in gpu_values], indices)
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
            "passes": settings["passes"], "resident_batches": resident,
            "dispatches_per_sample": sample_dispatches,
            "execution_mode": report.get("execution_mode", "serial_readback"),
            "pixel_dispatches_per_batch": pixel_dispatches,
            "warmup_batches": settings["warmup"], "measured_batches": settings["samples"],
        },
        "gpu_compute_window": gpu,
        "gpu_batch_cadence": marker_cadence(
            timed, sample_dispatches, pixel_dispatches)
            if len(timed) == len(samples) else {
                "available": False, "reason": "incomplete_measured_device_markers"},
        "host_request_to_readback": distribution(
            [float(r["host_request_to_readback_usec"]) for r in samples],
            [r["batch_index"] for r in samples]),
        "host_validation": distribution(
            [float(r["host_validation_usec"]) for r in samples],
            [r["batch_index"] for r in samples])
            if report["schema_version"] >= 2 else {"available": False, "samples": 0},
        "host_request_to_validated": distribution(
            [float(r["host_request_to_validated_usec"]) for r in samples],
            [r["batch_index"] for r in samples])
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
    if report["settings"].get("resident_batches", 1) != baseline["settings"].get("resident_batches", 1):
        raise ValueError("Incompatible native GPU readback cadence: resident_batches")
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
              "host_request_to_validated_usec", "pixel_dispatches_per_second",
              "gpu_start_gap_usec", "device_frame_delta")
    pixels = report["settings"]["width"] * report["settings"]["height"]
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        previous = None
        for record in report["records"]:
            row = {key: record.get(key) for key in fields}
            if previous is not None and (
                    type(previous.get("gpu_start_ns")) is int and
                    type(record.get("gpu_start_ns")) is int and
                    type(previous.get("device_frame")) is int and
                    type(record.get("device_frame")) is int):
                delta_ns = record["gpu_start_ns"] - previous["gpu_start_ns"]
                delta_frames = record["device_frame"] - previous["device_frame"]
                if delta_ns > 0 and delta_frames >= 0:
                    row["gpu_start_gap_usec"] = delta_ns / 1000.0
                    row["device_frame_delta"] = delta_frames
            elapsed = record.get("gpu_compute_window_usec")
            row["pixel_dispatches_per_second"] = (
                pixels * record["dispatches"] * 1_000_000.0 / float(elapsed)
                if elapsed is not None else None)
            writer.writerow(row)
            previous = record


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
    print(f"GPU low/high outlier batch indices: {gpu.get('low_outlier_batch_indices', [])} / "
          f"{gpu.get('high_outlier_batch_indices', [])}")
    cadence = result["gpu_batch_cadence"]
    if cadence["available"]:
        print(f"Device batch start cadence: p50={cadence['start_to_start_usec']['p50_usec']} us; "
              f"elapsed dispatch rate={cadence['dispatch_rate_per_second']:.2f}/s "
              f"(including inter-batch intervals)")
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
