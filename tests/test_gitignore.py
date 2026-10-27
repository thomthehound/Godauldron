"""Keep disposable local outputs out of Git without hiding Godot source metadata."""
from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GitIgnoreContract(unittest.TestCase):
    def test_native_outputs_ignored_and_godot_metadata_visible(self) -> None:
        expected = {
            ".native-build/generated/persistent_image.spv": True,
            ".native-rd-windows-build/Release/godauldron_native_rd_workload.dll": True,
            "experiments/native-rd-windows/manifest.json": True,
            "experiments/native-vulkan-provider/bin/native_provider.so": True,
            "native_rd_amd_resident4.json": True,
            "native_rd_amd_resident4.analysis.json": True,
            "native_rd_amd_resident4.csv": True,
            "native_rd_amd_profile.zip": True,
            "assets/showcase/makehuman_reference.glb.import": False,
            "assets/showcase/lee_perry_smith_color.jpg.import": False,
            "scripts/experiment_run.gd.uid": False,
            "native/vulkan_provider/package/native_persistent_workload_effect.gd.uid": False,
            "assets/showcase/makehuman_reference_young_caucasian_female_special_suit.png": False,
            "experiments/showcase-example/manifest.json": False,
        }
        for relative, ignored in expected.items():
            with self.subTest(path=relative):
                result = subprocess.run(
                    ["git", "check-ignore", "--no-index", "-q", "--", relative],
                    cwd=ROOT, capture_output=True, text=True, check=False)
                self.assertIn(result.returncode, (0, 1), result.stderr)
                self.assertEqual(result.returncode == 0, ignored)


if __name__ == "__main__":
    unittest.main()
