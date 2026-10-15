"""Manifest contract regression tests."""
import json
import tempfile
import unittest
from pathlib import Path
from tools.validate_manifests import scan_manifests, validate_manifest

class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scenes").mkdir()
        (self.root / "scenes" / "example.tscn").write_text("[gd_scene format=3]\n")
        self.data = {
            "schema_version": 1, "id": "org.example.sample",
            "display_name": "Sample", "category": "Diagnostics", "description": "Example",
            "entry_scene": "res://scenes/example.tscn",
            "parameters": [{"id": "count", "label": "Count", "type": "int",
                            "default": 4, "min": 1, "max": 10, "step": 1},
                           {"id": "enabled", "label": "Enabled", "type": "bool", "default": True}]
        }

    def test_valid(self):
        self.assertEqual(validate_manifest(self.data, self.root), [])

    def test_path_traversal(self):
        self.data["entry_scene"] = "res://../outside.tscn"
        self.assertIn("within the project", " ".join(validate_manifest(self.data, self.root)))

    def test_reject_bool_as_integer(self):
        self.data["parameters"][0]["default"] = True
        self.assertIn("must be integer", " ".join(validate_manifest(self.data, self.root)))

    def test_duplicate_parameters(self):
        self.data["parameters"].append(self.data["parameters"][0].copy())
        self.assertIn("duplicated", " ".join(validate_manifest(self.data, self.root)))

    def test_choice_parameter(self):
        self.data["parameters"].append({
            "id": "material", "label": "Material", "type": "choice",
            "default": "matte", "options": [
                {"value": "matte", "label": "Matte"},
                {"value": "polished", "label": "Polished"},
            ],
        })
        self.assertEqual(validate_manifest(self.data, self.root), [])
        self.data["parameters"][-1]["default"] = "absent"
        self.assertIn("must match an option", " ".join(validate_manifest(self.data, self.root)))
        self.data["parameters"][-1]["default"] = "matte"
        self.data["parameters"][-1]["options"][1]["value"] = "matte"
        self.assertIn("duplicated", " ".join(validate_manifest(self.data, self.root)))

    def test_duplicate_experiments(self):
        for name in ("one", "two"):
            folder = self.root / "experiments" / name
            folder.mkdir(parents=True)
            (folder / "manifest.json").write_text(json.dumps(self.data))
        self.assertIn("duplicate experiment id", " ".join(scan_manifests(self.root)))

if __name__ == "__main__":
    unittest.main()
