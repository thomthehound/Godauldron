"""Validate autonomous RD throughput without mislabeling host timing as GPU time."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def validate(data: dict, *, physical: bool) -> None:
    if (data.get("schema_version") != 1 or
            data.get("capture_type") != "godauldron_native_rd_autonomous_stream" or
            data.get("execution_mode") != "autonomous_inflight" or
            data.get("backend") != "d3d12" or
            data.get("validated") is not True):
        raise ValueError("Invalid sustained native RD report identity")
    s = data.get("settings", {})
    expected_mode = "physical_amd" if physical else "software"
    if s.get("mode") != expected_mode:
        raise ValueError("Sustained RD acceptance mode does not match request")
    width, height = s.get("width"), s.get("height")
    passes, resident = s.get("passes"), s.get("resident_batches")
    slots, warmup, samples = s.get("slots"), s.get("warmup"), s.get("samples")
    if (any(type(n) is not int for n in
            (width, height, passes, resident, slots, warmup, samples)) or
            not (1 <= width <= 2048 and 1 <= height <= 2048 and
                 width * height <= 1024 * 1024) or
            not (1 <= passes <= 32 and 1 <= resident <= 256 and
                 passes * resident <= 2048) or
            not (2 <= slots <= 4 and slots <= warmup <= 64 and
                 2 <= samples <= 1024)):
        raise ValueError("Invalid sustained workload bounds")
    adapter = data.get("adapter_provenance", {})
    if adapter.get("device_luid_matched") is not True or adapter.get("backend") != "d3d12":
        raise ValueError("Actual Godot D3D12 device identity not established")
    if physical:
        if (adapter.get("verified_physical_amd") is not True or
                adapter.get("verified_software") is not False or
                adapter.get("vendor_id") != 0x1002 or
                adapter.get("software_flag") is not False):
            raise ValueError("Physical AMD identity unverified")
    elif adapter.get("verified_software") is not True:
        raise ValueError("WARP identity unverified")
    m = data.get("measurement", {})
    elapsed = m.get("elapsed_usec")
    if (type(elapsed) is not int or elapsed <= 0 or
            m.get("measured_submissions") != samples or
            m.get("total_submissions_including_warmup") != samples + warmup or
            m.get("dispatches_per_submission") != passes * resident or
            m.get("clock") != "Time.get_ticks_usec monotonic host clock" or
            "NOT GPU execution time" not in m.get("scope", "")):
        raise ValueError("Sustained host measurement lacks valid scope or counts")
    for key, expected in (
        ("completed_dispatches_per_second", samples * passes * resident * 1e6 / elapsed),
        ("completed_pixel_dispatches_per_second",
         samples * passes * resident * width * height * 1e6 / elapsed),
    ):
        value = m.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or not math.isclose(
                value, expected, rel_tol=1e-10):
            raise ValueError(f"Invalid sustained throughput {key}")
    cpu = data.get("appliance_cpu", {})
    if (any(type(cpu.get(k)) is not int or cpu[k] < 0 for k in
            ("measured_record_calls_usec", "measured_callback_usec",
             "post_measurement_full_validation_usec")) or
            cpu.get("sentinel_checked_submissions") != samples + warmup or
            "excludes" not in cpu.get("scope", "")):
        raise ValueError("Appliance overhead is not separately accounted")
    life = data.get("resource_lifecycle", {})
    if (life.get("ring_slots") != slots or
            life.get("high_water_in_flight") != slots or
            life.get("created_slots") != slots or
            life.get("released_slots") != slots):
        raise ValueError("Bounded GPU resources were not fully used and retired")
    if data.get("final_output_correct_pixels") != width * height:
        raise ValueError("Final output not fully validated")
    gpu = data.get("gpu_timing", {})
    if gpu.get("available") is not False or "No GPU timestamps" not in gpu.get("reason", ""):
        raise ValueError("Host throughput cannot masquerade as GPU clock timing")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--mode", required=True, choices=["physical_amd", "software"])
    args = parser.parse_args()
    data = json.loads(args.report.read_text(encoding="utf-8"))
    validate(data, physical=args.mode == "physical_amd")
    m = data["measurement"]
    cpu = data["appliance_cpu"]
    print(f"Native RD sustained run validated: {m['measured_submissions']} samples; "
          f"dispatches/s={m['completed_dispatches_per_second']:.2f} "
          f"host-interval; CPU record/callback={cpu['measured_record_calls_usec']}/"
          f"{cpu['measured_callback_usec']} us; NOT GPU execution time")


if __name__ == "__main__":
    main()
