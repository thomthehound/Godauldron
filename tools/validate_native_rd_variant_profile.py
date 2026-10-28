"""Validate actual matched-shader RD variant path measurements and provenance."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

PATHS = ("source_compile_and_build", "resident_spirv_byte_match", "direct_resident_id")


def number(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        raise ValueError(f"{name}: expected a number")
    result = float(value)
    if not math.isfinite(result) or result < 0:
        raise ValueError(f"{name}: invalid duration")
    return result


def check_distribution(summary: dict, values: list[float], label: str) -> None:
    if summary.get("count") != len(values):
        raise ValueError(f"{label}: incorrect sample count")
    values.sort()
    if not values:
        if any(summary.get(key) is not None for key in (
                "mean_usec", "p50_usec", "p95_usec", "p99_usec",
                "minimum_usec", "maximum_usec")):
            raise ValueError(f"{label}: fabricated measurement")
        return

    def percentile(fraction: float) -> float:
        x = fraction * (len(values) - 1)
        lower = int(x)
        return values[lower] + (values[min(lower + 1, len(values) - 1)]
                                - values[lower]) * (x - lower)

    expected = {
        "mean_usec": sum(values) / len(values),
        "p50_usec": percentile(.50),
        "p95_usec": percentile(.95),
        "p99_usec": percentile(.99),
        "minimum_usec": values[0],
        "maximum_usec": values[-1],
    }
    for key, actual in expected.items():
        reported = number(summary.get(key), f"{label}.{key}")
        if not math.isclose(reported, actual, rel_tol=1e-5, abs_tol=1e-3):
            raise ValueError(f"{label}.{key}: summary differs from measured samples")


def validate(report: dict, *, physical: bool = False) -> None:
    if report.get("schema_version") != 1 or \
            report.get("capture_type") != "native_rd_variant_path_comparison" or \
            report.get("validated") is not True:
        raise ValueError("Not a validated native RD variant path comparison")
    settings = report["settings"]
    warmup, samples = settings["warmup"], settings["samples"]
    if type(warmup) is not int or type(samples) is not int or \
            not 1 <= warmup <= 8 or not 2 <= samples <= 64:
        raise ValueError("Invalid sample bounds")
    device = report["device"]
    if device["backend"] not in ("d3d12", "vulkan"):
        raise ValueError("Unsupported GPU backend")
    if physical or settings["mode"] == "physical_amd":
        evidence = device["windows_dxgi_verification"]
        if device["backend"] != "d3d12" or \
                device["physical_amd_verified"] is not True or \
                evidence.get("device_luid_matched") is not True or \
                evidence.get("verified_physical_amd") is not True or \
                evidence.get("vendor_id") != 0x1002:
            raise ValueError("Missing verified physical AMD device")
    if settings["mode"] == "software" and device["physical_amd_verified"]:
        raise ValueError("Software profile falsely claims physical AMD")
    records = report["records"]
    if len(records) != (warmup + samples) * len(PATHS):
        raise ValueError("Missing or extra path trial records")
    gpu_resolved = 0
    for i, record in enumerate(records):
        trial, position = divmod(i, len(PATHS))
        if record.get("path") != PATHS[position] or \
                record.get("trial") != trial or \
                record.get("warmup") is not (trial < warmup) or \
                record.get("variant_id") != trial + 2 or \
                record.get("gpu_batch_index") != i + 1:
            raise ValueError("Trial alignment, variant ID or GPU batch order changed")
        for key in ("host_request_to_readback_usec", "native_shader_create_host_usec",
                    "native_pipeline_create_host_usec", "native_descriptor_create_host_usec"):
            number(record.get(key), key)
        native = record.get("native_reload_host_usec")
        selection = record.get("native_selection_host_usec")
        lookup = record.get("native_lookup_host_usec")
        compiler = record.get("compiler_request_host_usec")
        if position == 0:
            for key in (native, compiler):
                number(key, "source compile/build duration")
            if number(native, "native build") < sum(
                number(record[k], k) for k in (
                    "native_shader_create_host_usec",
                    "native_pipeline_create_host_usec",
                    "native_descriptor_create_host_usec")):
                raise ValueError("Native build cannot be shorter than its API stages")
            if selection is not None or lookup is not None:
                raise ValueError("Source build cannot claim ID selection")
        elif position == 1:
            number(native, "SPIR-V resident-byte match")
            if compiler is not None or selection is not None or lookup is not None:
                raise ValueError("Byte match conflated with compiler or ID selection")
        else:
            number(selection, "ID selection")
            if number(lookup, "ID lookup") > selection:
                raise ValueError("ID lookup is longer than native selection")
            if compiler is not None or native is not None:
                raise ValueError("Direct ID selection invoked another path")
        if position != 0 and any(
                record[k] != 0 for k in (
                    "native_shader_create_host_usec",
                    "native_pipeline_create_host_usec",
                    "native_descriptor_create_host_usec")):
            raise ValueError("Resident selection created a GPU resource")
        gpu = record.get("gpu_compute_window_usec")
        if gpu is not None:
            if number(gpu, "GPU timestamp") <= 0 or \
                    type(record.get("gpu_device_frame")) is not int:
                raise ValueError("Invalid resolved GPU marker interval")
            if not record["warmup"]:
                gpu_resolved += 1
        elif record.get("gpu_device_frame") is not None:
            raise ValueError("GPU frame reported without device timestamp")
    timing = report["gpu_timing"]
    required = samples * len(PATHS)
    if timing.get("required_measured") != required or \
            timing.get("resolved_measured") != gpu_resolved or \
            timing.get("available") is not (gpu_resolved == required):
        raise ValueError("GPU timestamp availability does not match observed samples")
    if physical and gpu_resolved != required:
        raise ValueError("Physical GPU timing is incomplete")
    if set(report["results"]) != set(PATHS):
        raise ValueError("Path distribution missing")
    for path in PATHS:
        section = report["results"][path]
        matched = [r for r in records if r["path"] == path and not r["warmup"]]
        if len(matched) != samples:
            raise ValueError("Path distributions include warmups or lost samples")
        compiler = [float(r["compiler_request_host_usec"]) for r in matched
                    if r["compiler_request_host_usec"] is not None]
        native = [float(r["native_reload_host_usec"] if path != PATHS[2] else
                        r["native_selection_host_usec"]) for r in matched]
        gpu = [float(r["gpu_compute_window_usec"]) for r in matched
               if r["gpu_compute_window_usec"] is not None]
        host = [float(r["host_request_to_readback_usec"]) for r in matched]
        for field, values in (
                ("compiler_host_usec", compiler),
                ("native_path_host_usec", native),
                ("gpu_compute_window_usec", gpu),
                ("host_request_to_readback_usec", host)):
            check_distribution(section[field], values, f"{path}.{field}")
    lifecycle = report["resource_lifecycle"]
    if lifecycle.get("phase") != "released" or \
            lifecycle.get("active_resources") is not False or \
            lifecycle.get("variant_resident_count") != 0 or \
            lifecycle.get("variant_release_retirements") != 3 or \
            lifecycle.get("variant_builds") != warmup + samples + 1 or \
            lifecycle.get("pipeline_creations") != warmup + samples + 1 or \
            lifecycle.get("variant_evictions") != max(0, warmup + samples - 2):
        raise ValueError("Pipeline residency / retirement does not match benchmark trials")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--mode", choices=("software", "physical_amd"), default="software")
    args = parser.parse_args()
    data = json.loads(args.report.read_text(encoding="utf-8"))
    validate(data, physical=args.mode == "physical_amd")
    print("Verified native RD variant path profile:",
          data["device"]["backend"], "samples=", data["settings"]["samples"])
    for path in PATHS:
        summary = data["results"][path]
        print(path, "native p50 usec=",
              summary["native_path_host_usec"].get("p50_usec"),
              " GPU p50 usec=", summary["gpu_compute_window_usec"].get("p50_usec"))
