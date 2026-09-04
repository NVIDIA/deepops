"""Regression tests for the 26.09 release-blocker fixes.

Run with: python3 -m unittest discover scripts/validation/tests
"""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class SlurmRunPartsTests(unittest.TestCase):
    def run_fixture(self, mode):
        source = (
            ROOT / "roles/slurm/templates/etc/slurm/shared/bin/run-parts.sh"
        ).read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefix = root / "slurm"
            bin_dir = prefix / "bin"
            parts = root / "parts"
            mocks = root / "mocks"
            output = root / "output"
            bin_dir.mkdir(parents=True)
            parts.mkdir()
            mocks.mkdir()

            rendered = root / "run-parts.sh"
            rendered.write_text(
                source.replace("{{ slurm_install_prefix }}", str(prefix)).replace(
                    "/var/log/slurm/prolog-epilog", str(root / "prolog-epilog.log")
                ),
                encoding="utf-8",
            )
            rendered.chmod(0o755)

            (bin_dir / "squeue").write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    case "$SQUEUE_MODE:$*" in
                      fail:*) exit 1 ;;
                      empty:*) exit 0 ;;
                      invalid:*"-o %C"*) echo invalid ;;
                      invalid:*"-o %D"*) echo 1 ;;
                      invalid:*) echo invalid ;;
                      valid:*"-o %C"*) grep -c '^processor' /proc/cpuinfo ;;
                      valid:*"-o %D"*) echo 1 ;;
                      valid:*) exit 0 ;;
                    esac
                    """
                ),
                encoding="utf-8",
            )
            (bin_dir / "squeue").chmod(0o755)
            (mocks / "logger").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            (mocks / "logger").chmod(0o755)

            for name in ("10-normal", "20-exclusive-test", "30-lastuserjob-test"):
                path = parts / name
                path.write_text(
                    f"#!/bin/sh\necho {name} >> \"$OUTPUT\"\n",
                    encoding="utf-8",
                )
                path.chmod(0o755)

            env = {
                **os.environ,
                "HOSTNAME": "node1",
                "OUTPUT": str(output),
                "PATH": f"{mocks}:{os.environ['PATH']}",
                "SLURM_JOBID": "42",
                "SLURM_JOB_USER": "test-user",
                "SQUEUE_MODE": mode,
            }
            result = subprocess.run(
                [str(rendered), str(parts)],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            lines = (
                output.read_text(encoding="utf-8").splitlines()
                if output.exists()
                else []
            )
            return result, lines

    def test_failed_scheduler_queries_run_only_unconditional_parts(self):
        result, lines = self.run_fixture("fail")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, ["10-normal"])

    def test_empty_scheduler_queries_run_only_unconditional_parts(self):
        result, lines = self.run_fixture("empty")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, ["10-normal", "30-lastuserjob-test"])

    def test_invalid_scheduler_output_fails_closed(self):
        result, lines = self.run_fixture("invalid")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, ["10-normal"])

    def test_complete_scheduler_queries_select_exclusive_and_last_user_parts(self):
        result, lines = self.run_fixture("valid")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            lines,
            ["10-normal", "20-exclusive-test", "30-lastuserjob-test"],
        )


class ReleaseBlockerSourceContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_login_guard_uses_platform_service_consistently(self):
        source = self.read("roles/slurm/tasks/login-compute-setup.yml")
        self.assertIn("ansible_os_family == 'RedHat'", source)
        self.assertIn("systemctl show {{ ssh_unit }}", source)
        self.assertIn("systemctl set-property {{ ssh_unit }}", source)
        self.assertIn("system.control/{{ ssh_unit }}.d", source)

    def test_peer_memory_transitions_legacy_before_loading_in_tree_module(self):
        source = self.read("roles/nvidia-peer-memory/tasks/main.yml")
        stop = source.index("Stop and disable legacy nv_peer_mem service")
        unload = source.index("Unload legacy nv_peer_mem module")
        load = source.index("Load in-tree nvidia_peermem module")
        self.assertLess(stop, unload)
        self.assertLess(unload, load)

    def test_pyxis_uses_command_scoped_apparmor_not_global_sysctl(self):
        tasks = self.read("roles/pyxis/tasks/main.yml")
        profile = self.read("roles/pyxis/templates/enroot-nsenter.apparmor.j2")
        self.assertNotIn("ansible.posix.sysctl", tasks)
        self.assertIn("/etc/apparmor.d/enroot-nsenter", tasks)
        self.assertIn("profile enroot-nsenter /usr/bin/enroot-nsenter", profile)
        self.assertIn("userns,", profile)

    def test_dgx_dcgm_selects_and_verifies_cuda13_package(self):
        defaults = self.read("roles/nvidia_dcgm/defaults/main.yml")
        tasks = self.read("roles/nvidia_dcgm/tasks/install-dgx.yml")
        self.assertIn("datacenter-gpu-manager-4-cuda13", defaults)
        self.assertIn("ansible_distribution_version is version('24.04', '>=')", tasks)
        self.assertIn("dcgm_dgx_selected_pkg_name in ansible_facts.packages", tasks)

    def test_slurm_dcgm_exporter_avoids_guarded_direct_driver_test(self):
        cluster = self.read("playbooks/slurm-cluster.yml")
        exporter = self.read("playbooks/slurm-cluster/nvidia-dcgm-exporter.yml")
        driver = self.read("playbooks/nvidia-software/nvidia-driver.yml")
        self.assertIn("nvidia_dcgm_exporter_driver_test_enabled: false", cluster)
        self.assertIn("nvidia_dcgm_exporter_driver_test_enabled | default(true)", exporter)
        self.assertIn("nvidia_driver_test_enabled | default(true) | bool", driver)

    def test_slurmd_exports_custom_prefix_for_enroot_hooks(self):
        source = self.read("roles/slurm/tasks/service-files.yml")
        self.assertIn("/etc/systemd/system/slurmd.service.d/10-slurm-path.conf", source)
        self.assertIn("PATH={{ slurm_install_prefix }}/bin", source)
        self.assertIn("{{ slurm_install_prefix }}/sbin", source)

    def test_exporter_mounts_custom_prefix_clients_on_path(self):
        source = self.read(
            "roles/prometheus-slurm-exporter/templates/docker.slurm-exporter.service.j2"
        )
        self.assertIn("--env PATH=/usr/local/bin:/usr/bin:/bin", source)
        for command in ("sdiag", "sinfo", "squeue"):
            self.assertIn(f"/bin/{command}:/usr/local/bin/{command}", source)


if __name__ == "__main__":
    unittest.main()
