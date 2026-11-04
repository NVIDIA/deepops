"""Keep offline chart/image preparation aligned with the deployment roles."""

from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[3]


class AirgapPinTests(unittest.TestCase):
    def setUp(self):
        self.skill = (ROOT / "skills/deploy-airgapped/SKILL.md").read_text()
        self.gpu = yaml.safe_load(
            (ROOT / "roles/nvidia-gpu-operator/defaults/main.yml").read_text()
        )

    def assert_references_match(self, text, pattern, expected):
        versions = re.findall(pattern, text)
        self.assertTrue(versions, f"No references matched {pattern!r}")
        for version in versions:
            with self.subTest(pattern=pattern, version=version):
                self.assertEqual(version, expected)

    def test_gpu_operator_chart_preparation_matches_role(self):
        for pattern in (
            r"Operator `(v[\d.]+)`",
            r"nvidia/gpu-operator --version (\S+)",
            r"gpu-operator-(v[\d.]+)\.tgz",
        ):
            self.assert_references_match(
                self.skill, pattern, self.gpu["gpu_operator_chart_version"]
            )

    def test_registry_images_and_archives_match_role(self):
        registry = yaml.safe_load(
            (ROOT / "roles/standalone-container-registry/defaults/main.yml").read_text()
        )["standalone_container_registry_image"]
        expected = registry.removeprefix("registry:")
        for path in (
            "skills/deploy-airgapped/SKILL.md",
            "docs/airgap/mirror-docker-images.md",
        ):
            with self.subTest(path=path):
                self.assert_references_match(
                    (ROOT / path).read_text(), r"registry[:-](\d+\.\d+\.\d+)", expected
                )

    def test_driver_image_render_matches_role_override(self):
        self.assert_references_match(
            self.skill,
            r"--set driver.version=([\d.]+)",
            self.gpu["gpu_operator_driver_version"],
        )


if __name__ == "__main__":
    unittest.main()
