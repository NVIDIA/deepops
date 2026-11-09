#!/usr/bin/env python3
"""Reuse the real-role harness and add CI-specific check-mode regressions.

Molecule stages this file under <workspace>/ci-tests. Direct local invocation
also works from its source location, without Docker or a Kubernetes cluster.
"""
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve()
ROLE = (HERE.parents[3] if HERE.parents[3].name == "nvsentinel"
        else HERE.parents[1] / "roles" / "nvsentinel")
sys.path.insert(0, str(ROLE / "tests"))
import test_role  # noqa: E402


class CiRoleTests(test_role.RoleTests):
    """Inherited tests execute include_role against strict external fixtures."""

    def test_check_mode_disabled_does_not_uninstall(self):
        # Catches a forced check_mode:false on the role's uninstall command.
        rc, output, trace, values = self.run_role(
            {"nvsentinel_enabled": False, "nvsentinel_mode": "invalid"},
            {"installed": True, "nodes": 0, "version": "v1.30.0"}, check=True)
        self.assertEqual(rc, 0, output)
        self.assertTrue(trace, output)
        self.assertTrue(all(command[:2] == ["helm", "list"] for command in trace), trace)
        self.assert_no_writes(trace)
        self.assertIsNone(values)

    def test_check_mode_single_node_reports_observe_without_install(self):
        # Catches skipped discovery or a lost single-GPU fallback in --check.
        rc, output, trace, values = self.run_role(
            {"nvsentinel_mode": "cordon"}, {"nodes": 1}, check=True)
        self.assertEqual(rc, 0, output)
        self.assertIn("stepping down", output)
        self.assertIn("observe", output)
        self.assertIn(["kubectl", "get", "nodes", "-l",
                       "nvidia.com/gpu.present=true", "-o", "json"], trace)
        self.assert_no_writes(trace)
        self.assertIsNone(values)

    def test_check_mode_unsafe_remediation_requests_still_fail(self):
        # Catches guards being skipped in check mode or hidden by the fallback.
        for variables, message in [
            ({"nvsentinel_mode": "remediate"}, "nvsentinel_allow_node_reboot"),
            ({"nvsentinel_mode": "remediate", "nvsentinel_allow_node_reboot": True,
              "nvsentinel_dry_run": True}, "dry-run"),
        ]:
            with self.subTest(variables=variables):
                rc, output, trace, _ = self.run_role(variables, {"nodes": 1}, check=True)
                self.assertNotEqual(rc, 0, output)
                self.assertIn(message, output)
                self.assert_no_writes(trace)


if __name__ == "__main__":
    unittest.main()
