"""Strict provenance and throughput checks for the autonomous GPU ring."""
import copy
import unittest

from tools.validate_native_rd_stream_profile import validate


def fixture():
    return {
        "schema_version": 1,
        "capture_type": "godauldron_native_rd_autonomous_stream",
        "execution_mode": "autonomous_inflight", "backend": "d3d12",
        "validated": True,
        "settings": {"mode": "physical_amd", "width": 13, "height": 9,
                     "passes": 3, "resident_batches": 2, "slots": 3,
                     "warmup": 3, "samples": 12},
        "adapter_provenance": {"backend": "d3d12", "device_luid_matched": True,
                               "verified_physical_amd": True,
                               "verified_software": False, "software_flag": False,
                               "vendor_id": 0x1002},
        "measurement": {
            "clock": "Time.get_ticks_usec monotonic host clock",
            "scope": "host end-to-end workload including readback; NOT GPU execution time",
            "elapsed_usec": 120000,
            "measured_submissions": 12,
            "total_submissions_including_warmup": 15,
            "dispatches_per_submission": 6,
            "completed_dispatches_per_second": 600.0,
            "completed_pixel_dispatches_per_second": 70200.0,
        },
        "appliance_cpu": {
            "scope": "record and callbacks only; excludes unrelated engine work",
            "measured_record_calls_usec": 100,
            "measured_callback_usec": 200,
            "post_measurement_full_validation_usec": 500,
            "sentinel_checked_submissions": 15,
        },
        "resource_lifecycle": {
            "ring_slots": 3, "high_water_in_flight": 3,
            "created_slots": 3, "released_slots": 3,
        },
        "gpu_timing": {
            "available": False, "reason": "No GPU timestamps in host throughput benchmark",
        },
        "final_output_correct_pixels": 117,
    }


class AutonomousStreamReportTests(unittest.TestCase):
    def test_validated_report(self):
        validate(fixture(), physical=True)

    def test_rejects_false_throughput_or_gpu_clock(self):
        for section, key, bad in (
            ("measurement", "completed_dispatches_per_second", 900.0),
            ("measurement", "scope", "pure GPU execution time"),
            ("gpu_timing", "available", True),
            ("resource_lifecycle", "released_slots", 2),
            ("appliance_cpu", "sentinel_checked_submissions", 12),
        ):
            with self.subTest(key=key):
                data = copy.deepcopy(fixture())
                data[section][key] = bad
                with self.assertRaises(ValueError):
                    validate(data, physical=True)


if __name__ == "__main__":
    unittest.main()
