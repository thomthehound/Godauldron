"""Validate on-device native RD GPU evidence; never turn host wait into GPU time."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def validate_summary(summary: dict, values: list[float], label: str) -> None:
    if summary.get("count") != len(values):
        raise ValueError(f"{label} sample count contradicts the source readings")
    fields = {
        "mean_usec": None, "p50_usec": None, "p95_usec": None,
        "p99_usec": None, "minimum_usec": None, "maximum_usec": None,
    }
    if values:
        ordered = sorted(values)

        def percentile(p: float) -> float:
            pos = p * (len(ordered) - 1)
            lo = int(math.floor(pos))
            hi = min(lo + 1, len(ordered) - 1)
            return ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo)

        fields = {
            "mean_usec": sum(ordered) / len(ordered),
            "p50_usec": percentile(0.50),
            "p95_usec": percentile(0.95),
            "p99_usec": percentile(0.99),
            "minimum_usec": ordered[0], "maximum_usec": ordered[-1],
        }
    for key, expected in fields.items():
        actual = summary.get(key)
        if expected is None:
            if actual is not None:
                raise ValueError(f"{label}.{key} must be unavailable")
        elif (type(actual) not in (int, float) or
              not math.isfinite(float(actual)) or
              not math.isclose(float(actual), expected, rel_tol=1e-8, abs_tol=1e-4)):
            raise ValueError(f"{label}.{key} contradicts measured samples")


def validate(data: dict, *, physical: bool) -> None:
    if data.get("schema_version") != 1 or data.get("capture_type") != "godauldron_native_rd_physical_device_compute":
        raise ValueError("Wrong native GPU report schema")
    if data.get("backend") != "d3d12" or not data.get("validated", False):
        raise ValueError("Report is not a successful D3D12 native workload run")
    settings = data.get("settings", {})
    if settings.get("mode") != ("physical_amd" if physical else "software"):
        raise ValueError("Mode does not match intended GPU acceptance")
    width = settings.get("width", 0)
    height = settings.get("height", 0)
    samples = settings.get("samples", 0)
    warmup = settings.get("warmup", 0)
    passes = settings.get("passes", 0)
    if not all(type(x) is int and x > 0 for x in [width, height, samples, warmup, passes]):
        raise ValueError("Invalid workload dimensions/sample counts")
    if width * height > 1024 * 1024 or samples > 64 or warmup > 32 or passes > 32:
        raise ValueError("Unbounded workload in report")
    provenance = data.get("adapter_provenance", {})
    if (provenance.get("backend") != "d3d12" or
            provenance.get("device_luid_matched") is not True):
        raise ValueError("D3D12 device and DXGI adapter are not proven identical")
    if physical:
        if (provenance.get("verified_physical_amd") is not True or
                provenance.get("verified_software") is not False or
                provenance.get("vendor_id") != 0x1002 or
                provenance.get("software_flag") is not False):
            raise ValueError("Actual physical AMD adapter is not proven")
    elif provenance.get("verified_software") is not True:
        raise ValueError("Software D3D12 device is not proven")

    records = data.get("records", [])
    if len(records) != samples + warmup:
        raise ValueError("Missing device workload samples")
    for i, record in enumerate(records):
        if (record.get("batch_index") != i or
                record.get("warmup") is not (i < warmup) or
                record.get("correct_pixels") != width * height or
                record.get("dispatches") != passes or
                type(record.get("host_request_to_readback_usec")) is not int or
                record["host_request_to_readback_usec"] <= 0):
            raise ValueError(f"Failed native GPU work/readback sample {i}")
    gpu = data.get("gpu_timing", {})
    if (gpu.get("source") != "RenderingDevice.capture_timestamp / get_captured_timestamp_gpu_time" or
            gpu.get("unit") != "microseconds" or
            gpu.get("required_samples") != samples):
        raise ValueError("Missing device-timestamp provenance")
    sampled = records[warmup:]
    valid = [r for r in sampled if isinstance(r.get("gpu_compute_window_usec"), (int, float)) and
             math.isfinite(float(r["gpu_compute_window_usec"])) and r["gpu_compute_window_usec"] > 0]
    if gpu.get("resolved_samples") != len(valid):
        raise ValueError("GPU device timestamp counts contradict sample data")
    if gpu.get("available") is not (len(valid) == samples):
        raise ValueError("GPU timestamp availability contradicts its recorded samples")
    validate_summary(gpu.get("summary", {}), [float(r["gpu_compute_window_usec"])
                     for r in valid], "device_gpu")
    if physical and len(valid) != samples:
        raise ValueError("Physical GPU timing is incomplete")
    host = data.get("host_readback_latency", {})
    if "NOT GPU compute time" not in host.get("scope", ""):
        raise ValueError("Host readback latency was conflated with device timing")
    validate_summary(host.get("summary", {}),
                     [float(r["host_request_to_readback_usec"]) for r in sampled],
                     "host_readback")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--mode", choices=["physical_amd", "software"], required=True)
    args = parser.parse_args()
    data = json.loads(args.report.read_text(encoding="utf-8"))
    validate(data, physical=args.mode == "physical_amd")
    print(f"Native GPU report verified: {args.mode} {data['settings']['samples']} measured samples; "
          f"device timestamps={data['gpu_timing']['resolved_samples']}; "
          f"GPU p50 usec={data['gpu_timing']['summary']['p50_usec']}")


if __name__ == "__main__":
    main()
