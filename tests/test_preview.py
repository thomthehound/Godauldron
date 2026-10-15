"""Rolling-release policy regressions."""
import unittest

from tools.fetch_preview import choose_asset, order


def release(tag: str, platform: str = "linux.x86_64", *, draft: bool = False) -> dict:
    return {
        "tag_name": tag,
        "draft": draft,
        "assets": [{
            "name": f"Godot_v{tag}_{platform}.zip",
            "browser_download_url": f"https://example.invalid/{tag}.zip",
        }],
    }


class PreviewSelectionTests(unittest.TestCase):
    def setUp(self):
        self.releases = [
            release("4.7.2-stable"),
            release("5.0-dev1"),
            release("4.8-beta1"),
            release("4.8-dev7"),
        ]

    def test_unrestricted_tracks_next_major(self):
        tag, _ = choose_asset(self.releases, "linux.x86_64")
        self.assertEqual(tag, "5.0-dev1")

    def test_major_limited_stays_on_compatible_line(self):
        tag, _ = choose_asset(self.releases, "linux.x86_64", major=4)
        self.assertEqual(tag, "4.8-beta1")

    def test_respects_platform_and_avoids_drafts(self):
        releases = [
            release("5.0-beta3", draft=True),
            release("5.0-beta2", platform="windows.x86_64"),
            release("4.8-beta1"),
        ]
        tag, _ = choose_asset(releases, "linux.x86_64")
        self.assertEqual(tag, "4.8-beta1")

    def test_missing_major_fails_explicitly(self):
        with self.assertRaisesRegex(RuntimeError, "No matching"):
            choose_asset(self.releases, "linux.x86_64", major=6)

    def test_version_ordering(self):
        self.assertGreater(order("4.8-beta1"), order("4.8-dev7"))
        self.assertGreater(order("4.8-rc1"), order("4.8-beta2"))
        self.assertGreater(order("4.8-stable"), order("4.8-rc2"))


if __name__ == "__main__":
    unittest.main()
