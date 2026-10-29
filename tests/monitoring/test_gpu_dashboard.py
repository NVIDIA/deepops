#!/usr/bin/env python3
"""Check the dashboard JSON and execute its selectors with promtool (no cluster)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def panels(items):
    for panel in items:
        yield panel
        yield from panels(panel.get("panels", []))


class GpuDashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dashboard = json.loads((ROOT / "src/dashboards/gpu-dashboard.json").read_text())
        cls.variables = {v["name"]: v for v in cls.dashboard["templating"]["list"]}

    def test_exporter_selectors_use_independent_instances(self):
        # Restoring the shared host:port assumption must fail this check.
        for panel in panels(self.dashboard["panels"]):
            for target in panel.get("targets", []):
                expr = target.get("expr", "")
                for metric, selector in re.findall(r"(\w+)\{([^}]+)\}", expr):
                    if metric.startswith("DCGM_"):
                        self.assertIn('instance="$gpu_instance"', selector, expr)
                    elif metric.startswith("node_"):
                        self.assertIn('instance="$node_instance"', selector, expr)

    def test_instance_variables_are_hidden_and_refresh(self):
        for name in ("gpu_instance", "node_instance"):
            variable = self.variables.get(name)
            self.assertIsNotNone(variable, name)
            self.assertEqual(variable["hide"], 2)
            self.assertEqual(variable["refresh"], 1)
            self.assertIn("$hostname", variable["query"])
            self.assertEqual(variable["datasource"], "$datasource")
            self.assertFalse(variable["multi"])
            self.assertFalse(variable["includeAll"])

    def test_queries_against_kubernetes_and_slurm_series(self):
        tool = shutil.which(os.environ.get("PROMTOOL", "promtool"))
        self.assertIsNotNone(tool, "Install promtool or set PROMTOOL to its path")
        # GPU and node exporter IPs intentionally differ. An unrelated node
        # catches a selector that accidentally drops the chosen-host filter.
        cases = [
            ("kubernetes", "gpu-worker", "192.0.2.10:9400", "192.0.2.20:9100",
             ',kubernetes_node="gpu-worker"', "gpu-worker"),
            ("kubernetes-custom-ports", "gpu-worker", "192.0.2.10:19400", "192.0.2.20:19100",
             ',kubernetes_node="gpu-worker"', "gpu-worker"),
            ("slurm", "slurm-worker.example", "slurm-worker.example:9400",
             "slurm-worker.example:9100", "", "slurm-worker"),
            ("slurm-ip-inventory", "192.0.2.30", "192.0.2.30:9400",
             "192.0.2.30:9100", "", "slurm-worker"),
        ]
        for layout, hostname, gpu, node, gpu_labels, nodename in cases:
            with self.subTest(layout=layout), tempfile.TemporaryDirectory() as temp:
                rules = []
                expected = []
                # Execute the actual PromQL inside Grafana's query_result.
                # Validate the actual extraction regex against result labels.
                for name, label, value in (("hostname", "hostname", hostname),
                                           ("gpu_instance", "instance", gpu),
                                           ("node_instance", "instance", node)):
                    variable = self.variables.get(name)
                    self.assertIsNotNone(variable, name)
                    query = variable["query"]
                    self.assertTrue(query.startswith("query_result(") and query.endswith(")"))
                    expr = query[len("query_result("):-1].replace("$hostname", hostname)
                    rules.append({"record": "dashboard_" + name, "expr": expr})
                    if name == "node_instance":
                        labels = f'instance="{node}",nodename="{nodename}"'
                        sample_value = 1
                    else:
                        labels = f'instance="{gpu}"{gpu_labels}'
                        sample_value = 100
                        if name == "hostname":
                            labels += f',hostname="{hostname}"'
                    rendered = "{" + labels + "}"
                    match = re.search(variable["regex"].strip("/"), rendered)
                    self.assertIsNotNone(match, (name, rendered))
                    self.assertEqual(match.group(1), value)
                    expected.append({"expr": "dashboard_" + name, "eval_time": "1m",
                                     "exp_samples": [{"labels": '{__name__="dashboard_' + name + '",' + labels + '}',
                                                      "value": sample_value}]})
                # Parse every panel query with real Prometheus, including range
                # selectors, arithmetic, and aggregations after substitution.
                for panel in panels(self.dashboard["panels"]):
                    for index, target in enumerate(panel.get("targets", [])):
                        expr = target.get("expr")
                        if expr:
                            expr = (expr.replace("$gpu_instance", gpu)
                                    .replace("$node_instance", node)
                                    .replace("$hostname", hostname)
                                    .replace("$__interval", "1m"))
                            rules.append({"record": f'panel_{panel["id"]}_{index}', "expr": expr})
                # Assert representative host/GPU panels select the chosen node.
                for expr, value in ((f'node_load1{{instance="{node}"}}', 2),
                                    (f'DCGM_FI_DEV_POWER_USAGE{{instance="{gpu}"}}', 100)):
                    record = next(r["record"] for r in rules if r["expr"] == expr)
                    labels = f'instance="{node}"' if value == 2 else f'instance="{gpu}"{gpu_labels}'
                    expected.append({"expr": record, "eval_time": "1m", "exp_samples": [
                        {"labels": '{__name__="' + record + '",' + labels + '}', "value": value}]})
                series = [
                    {"series": f'DCGM_FI_DEV_POWER_USAGE{{instance="{gpu}"{gpu_labels}}}', "values": "100 100"},
                    {"series": f'node_uname_info{{instance="{node}",nodename="{nodename}"}}', "values": "1 1"},
                    {"series": f'node_load1{{instance="{node}"}}', "values": "2 2"},
                    {"series": 'DCGM_FI_DEV_POWER_USAGE{instance="192.0.2.99:9400",kubernetes_node="other-worker"}', "values": "900 900"},
                    {"series": 'node_uname_info{instance="192.0.2.99:9100",nodename="other-worker"}', "values": "1 1"},
                    {"series": 'node_load1{instance="192.0.2.99:9100"}', "values": "9 9"},
                ]
                # The hostname dropdown lists all GPU nodes, not just the selection.
                expected[0]["exp_samples"].append({"labels": '{__name__="dashboard_hostname",hostname="other-worker",instance="192.0.2.99:9400",kubernetes_node="other-worker"}', "value": 900})
                rules_path = Path(temp) / "rules.yml"
                rules_path.write_text(json.dumps({"groups": [{"name": "dashboard", "rules": rules}]}))
                tests_path = Path(temp) / "tests.yml"
                tests_path.write_text(json.dumps({"rule_files": [str(rules_path)], "evaluation_interval": "1m",
                                                  "tests": [{"interval": "1m", "input_series": series,
                                                             "promql_expr_test": expected}]}))
                result = subprocess.run([tool, "test", "rules", str(tests_path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
