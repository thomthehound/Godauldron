"""Tamper-proof domain/accounting checks for native variant path profiles."""
from __future__ import annotations

import copy
import unittest

from tools.validate_native_rd_variant_profile import PATHS, validate


def fixture() -> dict:
    warmup, samples = 1, 2
    records = []
    for trial in range(warmup + samples):
        for position, path in enumerate(PATHS):
            record = {
                "path": path, "trial": trial, "warmup": trial < warmup,
                "variant_id": trial + 2, "gpu_batch_index": trial * 3 + position + 1,
                "host_request_to_readback_usec": 500,
                "compiler_request_host_usec": 800 if position == 0 else None,
                "native_reload_host_usec": (200 if position == 0 else
                                           12 if position == 1 else None),
                "native_shader_create_host_usec": 40 if position == 0 else 0,
                "native_pipeline_create_host_usec": 80 if position == 0 else 0,
                "native_descriptor_create_host_usec": 20 if position == 0 else 0,
                "native_lookup_host_usec": 1 if position == 2 else None,
                "native_selection_host_usec": 5 if position == 2 else None,
                "gpu_compute_window_usec": 20.0,
                "gpu_device_frame": trial * 3 + position + 1,
            }
            records.append(record)
    results = {}
    for path in PATHS:
        results[path] = {
            "compiler_host_usec": {"count": samples if path == PATHS[0] else 0},
            "native_path_host_usec": {"count": samples},
            "gpu_compute_window_usec": {"count": samples},
            "host_request_to_readback_usec": {"count": samples},
        }
    return {
        "schema_version": 1, "capture_type": "native_rd_variant_path_comparison",
        "validated": True,
        "settings": {"mode": "software", "warmup": warmup, "samples": samples},
        "device": {"backend": "d3d12", "physical_amd_verified": False,
                   "windows_dxgi_verification": {"verified_software": True}},
        "records": records, "results": results,
        "gpu_timing": {"required_measured": 6, "resolved_measured": 6,
                       "available": True},
        "resource_lifecycle": {
            "phase": "released", "active_resources": False,
            "variant_resident_count": 0, "variant_release_retirements": 3,
            "variant_builds": 4, "pipeline_creations": 4,
            "variant_evictions": 1,
        },
    }


class VariantPathProvenanceTest(unittest.TestCase):
    def test_matching_shader_paths_and_missing_gpu_time(self) -> None:
        report = fixture()
        validate(report)
        report["records"][4]["gpu_compute_window_usec"] = None
        report["records"][4]["gpu_device_frame"] = None
        report["gpu_timing"].update(available=False, resolved_measured=5)
        report["results"][PATHS[1]]["gpu_compute_window_usec"]["count"] = 1
        validate(report)
        with self.assertRaisesRegex(ValueError, "physical AMD"):
            validate(report, physical=True)

    def test_domain_mixups_and_eviction_fabrication(self) -> None:
        edits = (
            lambda r: r["records"][5].update(compiler_request_host_usec=100),
            lambda r: r["records"][4].update(native_pipeline_create_host_usec=1),
            lambda r: r["records"][3].update(native_reload_host_usec=30),
            lambda r: r["records"][5].update(native_lookup_host_usec=9),
            lambda r: r["records"][4].update(variant_id=99),
            lambda r: r["records"][5].update(gpu_batch_index=100),
            lambda r: r["resource_lifecycle"].update(variant_evictions=0),
            lambda r: r["gpu_timing"].update(resolved_measured=5),
        )
        for edit in edits:
            with self.subTest(edit=edit):
                report = copy.deepcopy(fixture())
                edit(report)
                with self.assertRaises(ValueError):
                    validate(report)


if __name__ == "__main__":
    unittest.main()
