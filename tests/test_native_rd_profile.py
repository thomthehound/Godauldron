"""High-signal GPU report provenance and physical-vs-software regression."""
from __future__ import annotations

import copy
import unittest

from tools.validate_native_rd_profile import validate
from tools.analyze_native_rd_profile import analyze, compare


def fixture(physical: bool) -> dict:
    return {
        "schema_version": 1,
        "capture_type": "godauldron_native_rd_physical_device_compute",
        "backend": "d3d12",
        "validated": True,
        "settings": {"mode": "physical_amd" if physical else "software",
                     "width": 13, "height": 9, "warmup": 1, "samples": 2, "passes": 3},
        "adapter_provenance": {
            "backend": "d3d12", "device_luid_matched": True,
            "verified_software": not physical, "verified_physical_amd": physical,
            "vendor_id": 0x1002 if physical else 0x1414,
            "software_flag": False},
        "records": [
            {"batch_index": i, "warmup": i == 0, "correct_pixels": 117,
             "dispatches": 3, "host_request_to_readback_usec": 1500,
             "gpu_compute_window_usec": 2.5}
            for i in range(3)],
        "gpu_timing": {
            "source": "RenderingDevice.capture_timestamp / get_captured_timestamp_gpu_time",
            "unit": "microseconds", "required_samples": 2,
            "resolved_samples": 2, "available": True,
            "summary": {"count": 2, "mean_usec": 2.5, "p50_usec": 2.5,
                        "p95_usec": 2.5, "p99_usec": 2.5,
                        "minimum_usec": 2.5, "maximum_usec": 2.5}},
        "host_readback_latency": {
            "scope": "request through readback NOT GPU compute time",
            "summary": {"count": 2, "mean_usec": 1500.0,
                        "p50_usec": 1500.0, "p95_usec": 1500.0,
                        "p99_usec": 1500.0, "minimum_usec": 1500.0,
                        "maximum_usec": 1500.0}}
    }


class NativeGPUProfileContract(unittest.TestCase):
    def test_verified_physical_amd_and_software(self) -> None:
        for physical in (True, False):
            with self.subTest(physical=physical):
                validate(fixture(physical), physical=physical)

    def test_cpu_wait_never_substitutes_for_missing_gpu_timestamp(self) -> None:
        record = fixture(True)
        record["records"][1]["gpu_compute_window_usec"] = None
        record["gpu_timing"]["resolved_samples"] = 1
        record["gpu_timing"]["available"] = False
        with self.assertRaises(ValueError):
            validate(record, physical=True)

    def test_wrong_adapter_luid_cannot_prove_hardware(self) -> None:
        record = fixture(True)
        record["adapter_provenance"]["device_luid_matched"] = False
        with self.assertRaises(ValueError):
            validate(record, physical=True)

    def test_software_never_reports_as_physical(self) -> None:
        record = fixture(False)
        record["settings"]["mode"] = "physical_amd"
        with self.assertRaises(ValueError):
            validate(record, physical=True)

    def test_gpu_summary_cannot_disagree_with_real_gpu_samples(self) -> None:
        record = fixture(True)
        record["records"][2]["gpu_compute_window_usec"] = 2_500_000.0
        with self.assertRaises(ValueError):
            validate(record, physical=True)

    def test_host_summary_cannot_disagree_with_readback_measurements(self) -> None:
        record = fixture(True)
        record["records"][1]["host_request_to_readback_usec"] = 9_999_999
        with self.assertRaises(ValueError):
            validate(record, physical=True)

    def test_tampered_or_malformed_gpu_sample_fails(self) -> None:
        for value in (-3.0, float("nan")):
            record = copy.deepcopy(fixture(True))
            record["records"][2]["gpu_compute_window_usec"] = value
            with self.assertRaises(ValueError):
                validate(record, physical=True)



def extended_fixture(physical: bool = True) -> dict:
    report = fixture(physical)
    report["schema_version"] = 2
    report["workload_geometry"] = {
        "image_pixels": 117, "output_bytes": 468,
        "workgroups_x": 2, "workgroups_y": 2, "workgroups_per_dispatch": 4,
        "storage_image_barriers_per_batch": 2, "pixel_dispatches_per_batch": 351,
    }
    for index, record in enumerate(report["records"]):
        record.update({
            "host_validation_usec": 50,
            "host_request_to_validated_usec": 1580,
            "device_frame": index * 2 + 1,
            "gpu_start_ns": index * 10_000 + 1_000_000,
            "gpu_end_ns": index * 10_000 + 1_002_500,
        })
    for field, value in (("host_validation", 50.0),
                         ("host_request_to_validated", 1580.0)):
        report[field] = {
            "unit": "microseconds",
            "scope": "CPU verification only" if field == "host_validation"
                     else "full wall time; NOT GPU compute time",
            "summary": {
                "count": 2, "mean_usec": value, "p50_usec": value,
                "p95_usec": value, "p99_usec": value,
                "minimum_usec": value, "maximum_usec": value,
            },
        }
    counts = {
        "completed_batches": 3, "dispatch_count": 9,
        "pipeline_creations": 1, "descriptor_creations": 1,
        "prepare_count": 1,
    }
    report["resource_lifecycle"] = {
        "after_last_readback": {"phase": "prepared", "active_resources": True, **counts},
        "after_release": {"phase": "released", "active_resources": False, **counts},
    }
    return report


class ExtendedNativeGPUProfileContract(unittest.TestCase):
    def test_new_schema_and_metric_domain_separation(self) -> None:
        report = extended_fixture()
        validate(report, physical=True)
        metrics = analyze(report)
        self.assertEqual(metrics["gpu_compute_window"]["p50_usec"], 2.5)
        self.assertEqual(metrics["host_request_to_readback"]["p50_usec"], 1500.0)
        self.assertEqual(metrics["host_validation"]["p50_usec"], 50.0)
        self.assertEqual(metrics["gpu_compute_window"]["pixel_dispatches_per_second"]["p50_usec"],
                         351 * 1_000_000 / 2.5)

    def test_geometry_timestamps_and_lifetime_cannot_be_fabricated(self) -> None:
        for modify in (
            lambda r: r["workload_geometry"].update(workgroups_x=99),
            lambda r: r["records"][1].update(gpu_end_ns=1_002_400),
            lambda r: r["records"][1].update(host_request_to_validated_usec=1520),
            lambda r: r["resource_lifecycle"]["after_release"].update(active_resources=True),
        ):
            with self.subTest(modify=modify):
                report = extended_fixture()
                modify(report)
                with self.assertRaises(ValueError):
                    validate(report, physical=True)

    def test_robust_high_tail_and_strict_comparability(self) -> None:
        current = extended_fixture()
        # Expand the source records with a plausible high-latency GPU tail.
        current["settings"]["samples"] = 12
        current["records"] = [copy.deepcopy(current["records"][0])]
        for i in range(1, 13):
            rec = copy.deepcopy(current["records"][1])
            rec["batch_index"] = i
            rec["warmup"] = False
            rec["device_frame"] = i * 2 + 1
            rec["gpu_start_ns"] = 1_000_000 + 10000 * i
            duration = 152_000 if i in (4, 8) else 35_000
            rec["gpu_end_ns"] = rec["gpu_start_ns"] + duration
            rec["gpu_compute_window_usec"] = duration / 1000
            current["records"].append(rec)
        # Update the claimed GPU summary from the measured source readings.
        from tools.analyze_native_rd_profile import distribution
        def summary(values: list[float]) -> dict:
            metrics = distribution(values)
            return {"count": metrics["samples"],
                    **{key: metrics[key] for key in (
                        "mean_usec", "p50_usec", "p95_usec", "p99_usec",
                        "minimum_usec", "maximum_usec")}}
        current["gpu_timing"]["required_samples"] = 12
        current["gpu_timing"]["resolved_samples"] = 12
        current["gpu_timing"]["summary"] = summary(
            [r["gpu_compute_window_usec"] for r in current["records"][1:])
        for key, value in (("host_readback_latency", 1500.0),
                           ("host_validation", 50.0),
                           ("host_request_to_validated", 1580.0)):
            current[key]["summary"] = {
                "count": 12, "mean_usec": value, "p50_usec": value,
                "p95_usec": value, "p99_usec": value,
                "minimum_usec": value, "maximum_usec": value}
        current["resource_lifecycle"]["after_last_readback"]["completed_batches"] = 13
        current["resource_lifecycle"]["after_release"]["completed_batches"] = 13
        current["resource_lifecycle"]["after_last_readback"]["dispatch_count"] = 39
        current["resource_lifecycle"]["after_release"]["dispatch_count"] = 39
        metrics = analyze(current)
        self.assertEqual(metrics["gpu_compute_window"]["high_outlier_batch_indices"], [4, 8])
        baseline = copy.deepcopy(current)
        self.assertEqual(compare(current, baseline)["gpu_p50_change_percent"], 0)
        baseline["adapter_provenance"]["device_id"] = 9999
        with self.assertRaises(ValueError):
            compare(current, baseline)


if __name__ == "__main__":
    unittest.main()
