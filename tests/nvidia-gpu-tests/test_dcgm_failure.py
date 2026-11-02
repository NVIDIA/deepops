#!/usr/bin/env python3
"""Exercise the real DCGM task locally with a fake dcgmi; no GPU required.

Run with: python3 tests/nvidia-gpu-tests/test_dcgm_failure.py
Requires PyYAML and ansible-playbook on PATH.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
ROLE = ROOT / "roles/nvidia-gpu-tests"


class DcgmFailureTest(unittest.TestCase):
    def test_exit_policy(self):
        tasks = yaml.safe_load((ROLE / "tasks/main.yml").read_text())
        task = next(task for task in tasks if task.get("register") == "dcgm")
        defaults = yaml.safe_load((ROLE / "defaults/main.yml").read_text())
        # Removing boolean normalization must break the string-false cases.
        cases = [
            ("default", [], False),
            ("boolean false", ["-e", '{"gpu_test_dcgm_fail_on_error": false}'], False),
            ("boolean true", ["-e", '{"gpu_test_dcgm_fail_on_error": true}'], True),
            ("string false", ["-e", "gpu_test_dcgm_fail_on_error=false"], False),
            ("string no", ["-e", "gpu_test_dcgm_fail_on_error=no"], False),
            ("string true", ["-e", "gpu_test_dcgm_fail_on_error=true"], True),
            ("string yes", ["-e", "gpu_test_dcgm_fail_on_error=yes"], True),
        ]
        with tempfile.TemporaryDirectory(prefix="dcgm-test-") as directory:
            temp = Path(directory)
            stub = temp / "dcgmi"
            stub.write_text('#!/bin/sh\n[ "$*" = "diag -r 3" ] || exit 99\nprintf "diagnostic fixture\\n"\nexit "$DIAG_RC"\n')
            stub.chmod(0o755)
            config = temp / "ansible.cfg"
            config.write_text("[defaults]\nretry_files_enabled = False\nhost_key_checking = False\n")
            play = [{
                "hosts": "localhost", "connection": "local", "gather_facts": False,
                "vars": defaults,
                "environment": {"PATH": str(temp) + os.pathsep + os.environ["PATH"]},
                "tasks": [task, {"name": "Verify diagnostic result", "assert": {"that": [
                    "dcgm.rc == expected_rc | int", "'diagnostic fixture' in dcgm.stdout"
                ]}}],
            }]
            playbook = temp / "test.yml"
            playbook.write_text(yaml.safe_dump(play))
            env = dict(os.environ, ANSIBLE_CONFIG=str(config), ANSIBLE_HOME=str(temp / "home"),
                       ANSIBLE_LOCAL_TEMP=str(temp / "local"), ANSIBLE_REMOTE_TEMP=str(temp / "remote"),
                       ANSIBLE_NOCOLOR="1")
            for name, extra, fail_on_error in cases:
                for rc in (0, 1):
                    with self.subTest(setting=name, diagnostic_rc=rc):
                        result = subprocess.run(
                            ["ansible-playbook", "-i", "localhost,", str(playbook),
                             "-e", f"expected_rc={rc}", *extra],
                            cwd=temp, env=dict(env, DIAG_RC=str(rc)),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
                        )
                        if rc:
                            self.assertIn("diagnostic fixture", result.stdout, result.stdout)
                        self.assertEqual(result.returncode, 2 if rc and fail_on_error else 0, result.stdout)
                        if not (rc and fail_on_error):
                            self.assertIn("All assertions passed", result.stdout, result.stdout)


if __name__ == "__main__":
    unittest.main()
