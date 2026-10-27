"""High-signal GPU report provenance and physical-vs-software regression."""
from __future__ import annotations

import copy
import unittest

from tools.validate_native_rd_profile import validate


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


if __name__ == "__main__":
    unittest.main()
