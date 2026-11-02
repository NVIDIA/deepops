"""Offline render contract for DeepOps monitoring values.

Run with KPS_CHART_DIR pointing at unpacked kube-prometheus-stack 92.14.0.
No cluster access or chart download is performed by these tests.
"""
import os
from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]
CHART = os.environ.get("KPS_CHART_DIR")


@unittest.skipUnless(CHART, "set KPS_CHART_DIR to the unpacked monitoring chart")
class TestMonitoringChart(unittest.TestCase):
    def test_rotating_control_plane_credentials_without_static_token(self):
        # A missing opt-out would mint a non-expiring credential; disabling
        # authentication instead would remove the scrapeClass reference.
        for filename in ("monitoring.yml", "monitoring-no-persist.yml"):
            with self.subTest(values=filename):
                result = subprocess.run(
                    ["helm", "template", "kube-prometheus-stack", CHART,
                     "--namespace", "monitoring", "--kube-version", "1.34.0",
                     "-f", str(ROOT / "config.example/helm" / filename)],
                    capture_output=True, text=True, check=True,
                )
                docs = [d for d in yaml.safe_load_all(result.stdout) if d]
                self.assertFalse(any(d.get("type") == "kubernetes.io/service-account-token"
                                     for d in docs))
                prom = next(d for d in docs if d["kind"] == "Prometheus")
                self.assertIs(prom["spec"]["automountServiceAccountToken"], True)
                sa = next(d for d in docs if d["kind"] == "ServiceAccount"
                          and d["metadata"]["name"] == prom["spec"]["serviceAccountName"])
                self.assertIs(sa["automountServiceAccountToken"], True)
                classes = {c["name"]: c for c in prom["spec"]["scrapeClasses"]}
                self.assertEqual(classes["kube-prometheus-stack-control-plane"]["authorization"], {
                    "type": "Bearer",
                    "credentialsFile": "/var/run/secrets/kubernetes.io/serviceaccount/token",
                })
                self.assertEqual(prom["spec"]["nodeSelector"]["kubernetes.io/os"], "linux")
                self.assertIn("node-role.kubernetes.io/control-plane", prom["spec"]["nodeSelector"])
                monitors = [d for d in docs if d["kind"] == "ServiceMonitor"
                            and d["metadata"]["name"] != "dcgm-exporter"]
                control = [d for d in monitors if d["metadata"]["name"].endswith(
                    ("apiserver", "kubelet", "coredns", "kube-controller-manager",
                     "kube-scheduler", "kube-etcd", "kube-proxy"))]
                self.assertGreaterEqual(len(control), 7)
                for monitor in control:
                    self.assertEqual(monitor["spec"]["scrapeClass"], "kube-prometheus-stack-control-plane")
                    for endpoint in monitor["spec"]["endpoints"]:
                        self.assertNotIn("authorization", endpoint)
                        if monitor["metadata"]["name"].endswith((
                                "apiserver", "kubelet", "kube-controller-manager", "kube-scheduler")):
                            self.assertEqual(endpoint["tlsConfig"]["ca"]["configMap"], {
                                "name": "kube-root-ca.crt", "key": "ca.crt"})
                operator = next(d for d in docs if d["kind"] == "ClusterRole"
                                and d["metadata"]["name"] == "kube-prometheus-stack-operator")
                self.assertTrue(all("*" not in rule["verbs"] for rule in operator["rules"]))
                deployment = next(d for d in docs if d["kind"] == "Deployment"
                                  and d["metadata"]["name"] == "kube-prometheus-stack-operator")
                args = deployment["spec"]["template"]["spec"]["containers"][0]["args"]
                selectors = [arg for arg in args if arg.startswith("--secret-field-selector=")]
                self.assertTrue(selectors)
                self.assertTrue(all("kubernetes.io/service-account-token" not in arg
                                    for arg in selectors))


if __name__ == "__main__":
    unittest.main()
