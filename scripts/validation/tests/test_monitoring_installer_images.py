"""Execute the installer offline, then render its actual argv with chart 92.14.0."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

import yaml

import test_deploy_monitoring

CHART = os.environ.get("KPS_CHART_DIR")
ROOT = Path(__file__).resolve().parents[3]
REAL_HELM = shutil.which("helm")
MIRRORS = {
    "PROMETHEUS_OPER_REPO": ("operator", "mirror.example:5443/monitoring/operator"),
    "PROMETHEUS_REPO": ("prometheus", "mirror.example:5443/monitoring/prometheus"),
    "ALERTMANAGER_REPO": ("alertmanager", "mirror.example:5443/monitoring/alertmanager"),
    "GRAFANA_REPO": ("grafana", "mirror.example:5443/monitoring/grafana"),
    "GRAFANA_WATCHER_REPO": ("sidecar", "mirror.example:5443/monitoring/sidecar"),
}


@unittest.skipUnless(CHART, "set KPS_CHART_DIR to the unpacked monitoring chart")
class TestInstallerImages(unittest.TestCase):
    def setUp(self):
        self.harness = test_deploy_monitoring.TestDeployMonitoringExit()
        self.harness.setUp()
        self.addCleanup(self.harness.tearDown)
        config = Path(self.harness.tmp) / "config/helm"
        config.mkdir()
        shutil.copy(ROOT / "config.example/helm/monitoring.yml", config)
        self.values = config / "monitoring.yml"

    def render(self, **env):
        result, _ = self.harness.run_script(STATUS_AFTER="deployed", **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (Path(self.harness.tmp) / "helm-args").read_bytes().decode().split("\0")[:-1]
        self.assertIn(args[0], ("install", "upgrade"))
        args = args[1:]
        if args[0] == "--install":
            args = args[1:]
        self.assertEqual(args[1], "prometheus-community/kube-prometheus-stack")
        version_index = args.index("--version")
        self.assertEqual(args[version_index + 1], "92.14.0")
        args[1] = CHART
        rendered = subprocess.run([REAL_HELM, "template", *args, "--kube-version", "1.34.0"],
                                  capture_output=True, text=True, check=True)
        docs = [d for d in yaml.safe_load_all(rendered.stdout) if d]
        images = {}
        for doc in docs:
            if doc["kind"] in ("Prometheus", "Alertmanager"):
                images[doc["kind"].lower()] = [doc["spec"]["image"]]
            if doc["kind"] == "Deployment":
                for container in doc["spec"]["template"]["spec"]["containers"]:
                    name = container["name"]
                    if name == "kube-prometheus-stack":
                        images["operator"] = [container["image"]]
                    elif name == "grafana":
                        images["grafana"] = [container["image"]]
                    elif name.startswith("grafana-sc-"):
                        images.setdefault("sidecar", []).append(container["image"])
        self.assertEqual(set(images), {"operator", "prometheus", "alertmanager", "grafana", "sidecar"})
        return images

    def test_default_images_are_unchanged(self):
        self.assertEqual(self.render(), {
            "operator": ["quay.io/prometheus-operator/prometheus-operator:v0.94.2"],
            "prometheus": ["quay.io/prometheus/prometheus:v3.15.1-distroless"],
            "alertmanager": ["quay.io/prometheus/alertmanager:v0.34.1"],
            "grafana": ["docker.io/grafana/grafana:13.2.4-distroless"],
            "sidecar": ["quay.io/kiwigrid/k8s-sidecar:2.14.1"] * 2,
        })

    def test_explicit_tag_replaces_default_without_changing_repository(self):
        images = self.render(**{var: mirror + ":custom-tag"
                                for var, (_, mirror) in MIRRORS.items()})
        for _, (component, mirror) in MIRRORS.items():
            self.assertTrue(all(image == mirror + ":custom-tag" for image in images[component]))

    def test_each_requested_mirror_replaces_only_its_effective_images(self):
        defaults = self.render()
        for variable, (component, mirror) in MIRRORS.items():
            with self.subTest(variable=variable):
                images = self.render(**{variable: mirror})
                # Preserve the chart-selected tag while replacing all registry/path
                # segments; an unused key or double-registry render fails here.
                self.assertEqual(images[component], [mirror + ":" + image.rsplit(":", 1)[1]
                                                      for image in defaults[component]])
                for other in images.keys() - {component}:
                    self.assertEqual(images[other], defaults[other])

    def test_explicit_tags_and_digests_render_without_duplicate_suffixes(self):
        digest = "a" * 64
        overrides = {var: mirror + ":custom@sha256:" + digest
                     for var, (_, mirror) in MIRRORS.items()}
        images = self.render(**overrides)
        for variable, (component, _) in MIRRORS.items():
            self.assertTrue(all(image == overrides[variable] for image in images[component]))

    def test_repo_only_mirror_retains_site_tag_and_digest(self):
        values = yaml.safe_load(self.values.read_text())
        digest = "b" * 64
        values["prometheus"]["prometheusSpec"]["image"] = {"tag": "site-tag", "sha": digest}
        self.values.write_text(yaml.safe_dump(values))
        images = self.render(PROMETHEUS_REPO="mirror.example/nested/prometheus")
        self.assertEqual(images["prometheus"], ["mirror.example/nested/prometheus:site-tag@sha256:" + digest])

    def test_digest_only_reference_retains_default_tag(self):
        defaults = self.render()
        digest = "c" * 64
        images = self.render(**{var: mirror + "@sha256:" + digest
                                for var, (_, mirror) in MIRRORS.items()})
        for _, (component, mirror) in MIRRORS.items():
            self.assertEqual(images[component], [mirror + ":" + image.rsplit(":", 1)[1] + "@sha256:" + digest
                                                 for image in defaults[component]])


if __name__ == "__main__":
    unittest.main()
