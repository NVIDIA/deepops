#!/usr/bin/env python3
"""Render-time checks for the optional log search (Loki + Alloy). No cluster needed."""
import json
import pathlib
import re
import shutil
import subprocess
import unittest

import jinja2
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]


def render(path, **ctx):
    return jinja2.Template((ROOT / path).read_text()).render(**ctx)


class LogSearch(unittest.TestCase):
    def test_loki_config_is_valid_yaml_with_retention(self):
        out = render("roles/loki/templates/loki-config.yml.j2", loki_http_listen_address="0.0.0.0",
                     loki_http_port=3100, loki_retention_period="168h")
        cfg = yaml.safe_load(out)
        self.assertEqual(cfg["limits_config"]["retention_period"], "168h")
        self.assertTrue(cfg["compactor"]["retention_enabled"])

    def test_loki_default_retention_is_7_days_multiple_of_24h(self):
        d = yaml.safe_load((ROOT / "roles/loki/defaults/main.yml").read_text())
        self.assertEqual(d["loki_retention_period"], "168h")
        self.assertEqual(int(d["loki_retention_period"][:-1]) % 24, 0)

    def test_alloy_config_collects_journal_and_slurm(self):
        out = render("roles/alloy/templates/config.alloy.j2", alloy_loki_url="http://m:3100/loki/api/v1/push",
                     alloy_journal_max_age="12h", alloy_collect_slurm_logs=True,
                     alloy_slurm_log_paths=["/var/log/slurm/*.log"], inventory_hostname_short="n1")
        self.assertIn("loki.source.journal", out)
        self.assertIn("/var/log/slurm/*.log", out)
        off = render("roles/alloy/templates/config.alloy.j2", alloy_loki_url="u", alloy_journal_max_age="1h",
                     alloy_collect_slurm_logs=False, alloy_slurm_log_paths=[], inventory_hostname_short="n1")
        self.assertNotIn("local.file_match", off)

    def test_off_by_default(self):
        self.assertFalse(yaml.safe_load((ROOT / "roles/grafana/defaults/main.yml").read_text())["grafana_enable_loki"])
        self.assertRegex((ROOT / "config.example/group_vars/slurm-cluster.yml").read_text(),
                         re.compile(r"^slurm_enable_log_search: false$", re.M))
        pb = (ROOT / "playbooks/slurm-cluster.yml").read_text()
        self.assertIn("slurm_enable_log_search | default(false)", pb)

    def test_dashboard_json_and_datasource_uid(self):
        d = json.loads((ROOT / "src/dashboards/cluster-logs-dashboard.json").read_text())
        self.assertEqual(d["title"], "Cluster logs")
        ds = yaml.safe_load(render("roles/grafana/templates/loki-datasource.yml.j2", grafana_loki_url="http://x:3100"))
        self.assertEqual(ds["datasources"][0]["uid"], "deepops-loki")
        self.assertIn('"uid": "deepops-loki"', (ROOT / "src/dashboards/cluster-logs-dashboard.json").read_text())

    def test_k8s_values_parse(self):
        for f in ("loki.yml", "alloy.yml", "loki-datasource.yaml"):
            yaml.safe_load((ROOT / "config.example/helm" / f).read_text())

    @unittest.skipUnless(shutil.which("helm"), "helm not installed")
    def test_helm_charts_render(self):
        r = subprocess.run(["bash", str(ROOT / "scripts/k8s/deploy_logging.sh"), "-t"],
                           env={"DEEPOPS_CONFIG_DIR": str(ROOT / "config.example"), "PATH": __import__("os").environ["PATH"],
                                "HOME": __import__("os").environ["HOME"]},
                           capture_output=True, text=True, timeout=300)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
