#!/usr/bin/env python3
"""Inert slurm.conf partition regressions; run with Ansible's Python.

The role template is rendered in memory with fixture facts. No host is
contacted and nothing is written.
"""
import os
from pathlib import Path
import unittest

from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar
import yaml

ROOT = Path(os.environ.get("DEEPOPS_TEST_ROOT", Path(__file__).resolve().parents[2]))
ROLE = ROOT / "roles/slurm"
DEFAULTS = yaml.safe_load((ROLE / "defaults/main.yml").read_text())
TEMPLATE = (ROLE / "templates" / DEFAULTS["slurm_conf_template"]).read_text()
FACTS = {"ansible_local": {
    "memory": {"total_mb": 1000},
    "topology": {"cpu_topology": {"sockets": "1", "cores_per_socket": "4",
                                  "threads_per_core": "2", "logical_cpus": "8"},
                 "gpu_topology": ["0-7"]}}}


class Partition(unittest.TestCase):
    def partition(self, **overrides):
        variables = {**DEFAULTS,
                     "groups": {"slurm-master": ["login01"], "slurm-node": ["node01"]},
                     "hostvars": {"node01": FACTS}, **overrides}
        rendered = Templar(loader=DataLoader(), variables=variables).template(TEMPLATE)
        lines = [line for line in rendered.splitlines() if line.startswith("PartitionName=")]
        self.assertEqual(len(lines), 1, rendered)
        return dict(field.split("=", 1) for field in lines[0].split())

    def test_oversubscribe_default_follows_gpu_management(self):
        for manage_gpus, expected in ((True, "NO"), (False, "EXCLUSIVE")):
            with self.subTest(slurm_manage_gpus=manage_gpus):
                partition = self.partition(slurm_manage_gpus=manage_gpus)
                self.assertEqual(partition["OverSubscribe"], expected)

    def test_oversubscribe_setting_is_used(self):
        for manage_gpus in (True, False):
            for value in ("NO", "EXCLUSIVE", "YES", "FORCE"):
                with self.subTest(slurm_manage_gpus=manage_gpus, slurm_oversubscribe=value):
                    partition = self.partition(slurm_manage_gpus=manage_gpus,
                                               slurm_oversubscribe=value)
                    self.assertEqual(partition["OverSubscribe"], value)


if __name__ == "__main__":
    unittest.main()
