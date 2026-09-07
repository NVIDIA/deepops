"""Regression tests for the 26.09 release-blocker fixes.

Run with: python3 -m unittest discover scripts/validation/tests
"""

import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
TRANSIENT_SERVICE = "systemd-run --wait --pipe --collect --quiet --"
GPU_TASK_PATHS = (
    "playbooks/nvidia-software/nvidia-driver.yml",
    "playbooks/nvidia-software/nvidia-cuda.yml",
    "playbooks/utilities/gpu-clocks.yml",
    "playbooks/utilities/nvidia-set-gpu-clocks.yml",
    "playbooks/nvidia-software/nvidia-mig.yml",
    "roles/nvidia-mig-manager/tasks/main.yml",
)


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
                    f'#!/bin/sh\necho {name} >> "$OUTPUT"\n',
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

    def tasks(self, path):
        documents = yaml.safe_load(self.read(path))
        tasks = []

        def visit(value):
            if isinstance(value, dict):
                if "command" in value or "shell" in value:
                    tasks.append(value)
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)

        visit(documents)
        return tasks

    def gpu_commands(self, path):
        commands = []
        for task in self.tasks(path):
            command = task.get("command", task.get("shell"))
            if isinstance(command, str) and (
                "nvidia-smi" in command
                or "nvidia-mig-parted apply" in command
                or "nvidia-mig-parted assert" in command
            ):
                commands.append((task, " ".join(command.split())))
        return commands

    def task_named(self, path, name):
        matches = [task for task in self.tasks(path) if task.get("name") == name]
        self.assertEqual(len(matches), 1, f"{path}: {name}")
        return matches[0]

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
        self.assertIn(
            "nvidia_dcgm_exporter_driver_test_enabled | default(true)", exporter
        )
        self.assertIn("nvidia_driver_test_enabled | default(true) | bool", driver)

    def test_privileged_gpu_commands_escape_the_ssh_cgroup(self):
        expected_commands = {
            "playbooks/nvidia-software/nvidia-driver.yml": ("nvidia-smi",),
            "playbooks/nvidia-software/nvidia-cuda.yml": ("nvidia-smi",),
            "playbooks/utilities/gpu-clocks.yml": ("nvidia-smi -acp UNRESTRICTED",),
            "playbooks/utilities/nvidia-set-gpu-clocks.yml": (
                "nvidia-smi -lgc {{ gpu_clock_lock }}",
                "nvidia-smi -rgc",
            ),
            "playbooks/nvidia-software/nvidia-mig.yml": (
                "nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader",
                "nvidia-mig-parted apply",
                "nvidia-mig-parted assert",
            ),
            "roles/nvidia-mig-manager/tasks/main.yml": (
                "nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader",
            ),
        }

        self.assertEqual(set(expected_commands), set(GPU_TASK_PATHS))
        for path, expected in expected_commands.items():
            with self.subTest(path=path):
                commands = self.gpu_commands(path)
                self.assertEqual(len(commands), len(expected))
                for fragment in expected:
                    matching = [
                        command for _, command in commands if fragment in command
                    ]
                    self.assertEqual(len(matching), 1, fragment)
                    command = matching[0]
                    self.assertIn(TRANSIENT_SERVICE, command)
                    self.assertLess(
                        command.index(TRANSIENT_SERVICE), command.index(fragment)
                    )

    def test_driver_check_is_not_exempt_from_transient_execution(self):
        commands = self.gpu_commands("playbooks/nvidia-software/nvidia-driver.yml")
        self.assertEqual(len(commands), 1)
        task, command = commands[0]
        self.assertEqual(task["name"], "test nvidia-smi")
        self.assertEqual(task["changed_when"], False)
        self.assertEqual(command, f"{TRANSIENT_SERVICE} nvidia-smi")

    def test_no_guarded_task_directly_executes_nvidia_smi(self):
        for path in GPU_TASK_PATHS:
            for _, command in self.gpu_commands(path):
                if "nvidia-smi" not in command:
                    continue
                with self.subTest(path=path, command=command):
                    self.assertIn(TRANSIENT_SERVICE, command)
                    self.assertLess(
                        command.index(TRANSIENT_SERVICE), command.index("nvidia-smi")
                    )

    def test_standalone_mig_operations_run_privileged(self):
        plays = yaml.safe_load(self.read("playbooks/nvidia-software/nvidia-mig.yml"))
        self.assertEqual(len(plays), 1)
        self.assertIs(plays[0]["become"], True)

    def test_standalone_mig_role_probe_runs_privileged(self):
        probe = self.task_named(
            "roles/nvidia-mig-manager/tasks/main.yml",
            "check for MIG capable devices",
        )
        self.assertIs(probe["become"], True)

    def test_mig_manager_install_tasks_require_successful_capability_probe(self):
        path = "roles/nvidia-mig-manager/tasks/main.yml"
        tasks = yaml.safe_load(self.read(path))
        tasks_by_name = {task["name"]: task for task in tasks}
        expected_conditions = {
            "Install MIG Manager (apt)": {
                "has_mig.rc == 0",
                "has_mig_parted.rc != 0",
                'ansible_os_family == "Debian"',
            },
            "Install MIG Manager (yum)": {
                "has_mig.rc == 0",
                "has_mig_parted.rc != 0",
                'ansible_os_family == "RedHat"',
            },
        }

        for name, expected in expected_conditions.items():
            with self.subTest(name=name):
                self.assertIn(name, tasks_by_name)
                self.assertEqual(set(tasks_by_name[name]["when"]), expected)

    def test_gpu_clock_tasks_use_command_without_shell_interpolation(self):
        path = "playbooks/utilities/nvidia-set-gpu-clocks.yml"
        expected = {
            "set the gpu clock to a specified amount": "not gpu_clock_reset",
            "reset the gpu clock to the default": "gpu_clock_reset",
        }
        for name, condition in expected.items():
            with self.subTest(name=name):
                task = self.task_named(path, name)
                self.assertIn("command", task)
                self.assertNotIn("shell", task)
                self.assertEqual(task["when"], condition)

    def test_mig_probes_fail_closed_on_non_capability_output(self):
        capability_value = "grep -E '^(Enabled|Disabled)$'"
        for path in (
            "playbooks/nvidia-software/nvidia-mig.yml",
            "roles/nvidia-mig-manager/tasks/main.yml",
        ):
            with self.subTest(path=path):
                probes = [
                    (task, command)
                    for task, command in self.gpu_commands(path)
                    if "--query-gpu=mig.mode.current" in command
                ]
                self.assertEqual(len(probes), 1)
                task, command = probes[0]
                self.assertEqual(task["failed_when"], False)
                self.assertIn("set -o pipefail", command)
                self.assertIn(capability_value, command)
                self.assertNotIn("grep -v", command)

        accepted = re.compile(r"^(Enabled|Disabled)$", re.MULTILINE)
        for output in ("No devices were found", "", "NVIDIA-SMI has failed"):
            with self.subTest(output=output):
                self.assertIsNone(accepted.search(output))

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
