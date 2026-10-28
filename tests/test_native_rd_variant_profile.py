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
    def stats(value: float | None, count: int) -> dict:
        return {"count": count, "mean_usec": value, "p50_usec": value,
                "p95_usec": value, "p99_usec": value,
                "minimum_usec": value, "maximum_usec": value}

    results = {}
    for path in PATHS:
        results[path] = {
            "compiler_host_usec": stats(800.0, samples) if path == PATHS[0]
                                  else stats(None, 0),
            "native_path_host_usec": stats(
                200.0 if path == PATHS[0] else 12.0 if path == PATHS[1] else 5.0,
                samples),
            "gpu_compute_window_usec": stats(20.0, samples),
            "host_request_to_readback_usec": stats(500.0, samples),
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


def balanced_fixture() -> dict:
    report = fixture()
    warmup, samples = 3, 3
    template_by_path = {r["path"]: r for r in report["records"][:3]}
    rows = []
    for trial in range(warmup + samples):
        for slot in range(3):
            path = PATHS[(trial + slot) % 3]
            row = copy.deepcopy(template_by_path[path])
            row.update(path=path, trial=trial, execution_slot=slot,
                       warmup=trial < warmup, variant_id=trial + 2,
                       gpu_batch_index=trial * 3 + slot + 1,
                       gpu_device_frame=trial * 3 + slot + 1)
            rows.append(row)
    report["schema_version"] = 2
    report["settings"].update(warmup=warmup, samples=samples)
    report["execution_order"] = {
        "method": "three_order_cyclic_rotation",
        "warmup_full_cycles": 1,
        "source_compilation_before_all_arms": True,
        "GPU_execution_counterbalanced": True,
        "source_pipeline_build_counterbalanced": False,
    }
    report["records"] = rows
    report["gpu_timing"].update(required_measured=9, resolved_measured=9)
    for path in PATHS:
        for section in report["results"][path].values():
            if section["count"] > 0:
                section["count"] = 3
    report["resource_lifecycle"].update(
        variant_builds=7, pipeline_creations=7, variant_evictions=4)
    return report


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

    def test_tampered_quantile_or_missing_gpu_timestamp_is_rejected(self) -> None:
        report = fixture()
        report["results"][PATHS[0]]["native_path_host_usec"]["p50_usec"] = 3.0
        with self.assertRaisesRegex(ValueError, "summary differs"):
            validate(report)

        report = fixture()
        report["records"][4]["gpu_compute_window_usec"] = None
        report["records"][4]["gpu_device_frame"] = None
        report["gpu_timing"].update(available=False, resolved_measured=5)
        # The original full-sample GPU summary cannot survive a missing
        # device timestamp without changing its count.
        with self.assertRaisesRegex(ValueError, "incorrect sample count"):
            validate(report)

    def test_counterbalanced_three_orders_and_causal_compilation(self) -> None:
        report = balanced_fixture()
        validate(report)
        measured = [r for r in report["records"] if not r["warmup"]]
        for slot in range(3):
            self.assertEqual({r["path"] for r in measured
                              if r["execution_slot"] == slot}, set(PATHS))
        for tamper in (
            lambda r: r["records"][4].update(path=PATHS[1]),
            lambda r: r["records"][4].update(execution_slot=0),
            lambda r: r["execution_order"].update(
                source_pipeline_build_counterbalanced=True),
            lambda r: r["settings"].update(samples=4),
        ):
            with self.subTest(tamper=tamper):
                bad = copy.deepcopy(report)
                tamper(bad)
                with self.assertRaises(ValueError):
                    validate(bad)

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
