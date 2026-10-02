#!/usr/bin/env python3
"""Inert Ansible command/dependency regressions; run with Ansible's Python."""
import os
from pathlib import Path
import shlex
import unittest

from ansible.parsing.dataloader import DataLoader
from ansible.playbook.conditional import Conditional
from ansible.template import Templar
import yaml

ROOT = Path(os.environ.get("DEEPOPS_TEST_ROOT", Path(__file__).resolve().parents[2]))
ROLE = ROOT / "roles/slurm"
TASKS = yaml.safe_load((ROLE / "tasks/build.yml").read_text())
DEFAULTS = yaml.safe_load((ROLE / "defaults/main.yml").read_text())


class LuaBuild(unittest.TestCase):
    def selected(self, task, variables):
        loader = DataLoader()
        templar = Templar(loader=loader, variables=variables)
        condition = Conditional(loader=loader)
        when = task.get("when", [])
        condition.when = [when] if isinstance(when, str) else when
        return condition.evaluate_conditional(templar, variables), templar

    def test_configure_flag_for_both_nvml_paths(self):
        for enabled, expected in ((False, False), (True, True), ("false", False), ("true", True)):
            for nvml in (False, True):
                with self.subTest(enabled=enabled, nvml=nvml):
                    variables = {**DEFAULTS, "slurm_build_lua": enabled,
                                 "slurm_build": True, "slurm_autodetect_nvml": nvml,
                                 "slurm_configure": "./configure --site-option",
                                 "slurm_configure_nvml": "./configure --site-option --with-nvml=/cuda"}
                    commands = []
                    for task in TASKS:
                        if task.get("name") != "configure":
                            continue
                        active, templar = self.selected(task, variables)
                        if active:
                            commands.append(shlex.split(templar.template(task["command"])))
                    self.assertEqual(len(commands), 1)
                    self.assertEqual("--with-lua" in commands[0], expected)
                    self.assertIn("--site-option", commands[0])
                    self.assertEqual("--with-nvml=/cuda" in commands[0], nvml)

    def test_package_is_opt_in_and_matches_distribution(self):
        for distro, family, varfile, module, package in (
            ("Ubuntu", "Debian", "ubuntu.yml", "apt", "liblua5.3-dev"),
            ("Rocky", "RedHat", "redhat.yml", "dnf", "lua-devel"),
        ):
            for enabled in (False, True):
                with self.subTest(distro=distro, enabled=enabled):
                    variables = {**DEFAULTS, **yaml.safe_load((ROLE / "vars" / varfile).read_text()),
                                 "slurm_build_lua": enabled, "ansible_distribution": distro,
                                 "ansible_os_family": family}
                    selected = []
                    for task in TASKS:
                        if task.get("name") != "install lua build dependencies":
                            continue
                        active, templar = self.selected(task, variables)
                        if active:
                            selected.append(templar.template(task[module])["name"])
                    self.assertEqual(selected, [[package]] if enabled else [])


if __name__ == "__main__":
    unittest.main()
