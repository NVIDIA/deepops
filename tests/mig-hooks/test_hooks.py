#!/usr/bin/env python3
"""Render the actual MIG apply command without running GPU operations.

Run using the project's Ansible Python environment:
  python tests/mig-hooks/test_hooks.py
"""
import os
from pathlib import Path
import shlex
import unittest

from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar
import yaml

ROOT = Path(os.environ.get("DEEPOPS_TEST_ROOT", Path(__file__).resolve().parents[2]))
PLAY = yaml.safe_load((ROOT / "playbooks/nvidia-software/nvidia-mig.yml").read_text())[0]
APPLY = next(task for task in PLAY["tasks"] if task.get("name") == "Apply MIG configuration")
DEFAULTS = yaml.safe_load((ROOT / "config.example/group_vars/all.yml").read_text())


class Hooks(unittest.TestCase):
    def render(self, values):
        variables = {"mig_manager_config": "/etc/mig/config.yml",
                     "mig_manager_profile": "all-disabled", **values}
        rendered = Templar(loader=DataLoader(), variables=variables).template(APPLY["command"])
        return shlex.split(rendered)

    def test_example_defaults_do_not_require_an_unmanaged_file(self):
        self.assertNotIn("-k", self.render(DEFAULTS))

    def test_unset_or_empty_hooks_omit_flag(self):
        for values in ({}, {"mig_manager_hooks": ""}):
            with self.subTest(values=values):
                self.assertNotIn("-k", self.render(values))

    def test_explicit_hooks_are_preserved_as_one_argument(self):
        # Includes a missing path: do not silently bypass an operator's hooks.
        for path in ("/etc/mig/custom-hooks.yaml", "/missing/hooks file.yaml"):
            with self.subTest(path=path):
                args = self.render({"mig_manager_hooks": path})
                self.assertEqual(args[args.index("-k") + 1:], [path])
                self.assertEqual(args[:6], ["systemd-run", "--wait", "--pipe",
                                            "--collect", "--quiet", "--"])
                self.assertIn("apply", args)


if __name__ == "__main__":
    unittest.main()
