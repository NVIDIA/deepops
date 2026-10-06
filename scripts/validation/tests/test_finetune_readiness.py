"""Offline readiness contracts: real cache files, inert scheduler/process boundary."""
import argparse
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SCRIPT = SCRIPTS / "validate_finetune.py"


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "fine-tuning readiness validator is missing")
        spec = importlib.util.spec_from_file_location("readiness", SCRIPT)
        self.validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.validator)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cache = Path(self.tmp.name)
        self.snapshot = self.cache / "models--example--model/snapshots" / ("a" * 40)
        self.snapshot.mkdir(parents=True)
        for name in ("config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"):
            (self.snapshot / name).write_text("{}")
        self.args = argparse.Namespace(cache_dir=str(self.cache), repo_id="example/model",
            revision="a" * 40, require_file=["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"],
            node="gpu-node", partition="gpu", container_image="registry.example#team/train@sha256:" + "b" * 64,
            timeout=5, gpu_smoke=False)
        self.node = ("NodeName=gpu-node NodeHostName=" + socket.gethostname() +
                     " State=IDLE Partitions=gpu CfgTRES=cpu=8,gres/gpu=2 AllocTRES=cpu=0,gres/gpu=0")
        self.partition = "PartitionName=gpu State=UP"
        self.commands = []
        self.fail_command = None
        self.smoke_output = "0, Example GPU"

    def run_command(self, command, timeout):
        self.commands.append(command)
        if command[0] == self.fail_command:
            return 1, "private output", "private failure"
        if command[:4] == ["scontrol", "show", "node", "--oneliner"]:
            return 0, self.node, ""
        if command[:4] == ["scontrol", "show", "partition", "--oneliner"]:
            return 0, self.partition, ""
        if command == ["enroot", "version"]:
            return 0, "3.5.0", ""
        if command == ["srun", "--help"]:
            return 0, "--container-image --container-mounts", ""
        if command[0] == "srun" and "--gpus=1" in command:
            return 0, self.smoke_output, ""
        self.fail("unexpected command: " + repr(command))

    def validate(self):
        with patch.object(self.validator, "run", side_effect=self.run_command):
            return self.validator.validate(self.args)

    def assert_not_ready(self, stage):
        result = self.validate()
        self.assertEqual(result["status"], "not_ready")
        self.assertFalse(result["ok"])
        self.assertFalse(result["training_validated"])
        self.assertIn(stage, [e["stage"] for e in result["errors"]])
        self.assertNotIn("private", json.dumps(result))
        return result

    def test_ready_is_not_training_and_never_submits_by_default(self):
        result = self.validate()
        self.assertEqual(result["status"], "ready")
        self.assertTrue(result["ok"])
        self.assertEqual(result["schema_version"], 1)
        self.assertFalse(result["training_validated"])
        self.assertFalse(result["gpu_smoke_ran"])
        self.assertEqual([c for c in self.commands if c[0] == "srun"], [["srun", "--help"]])

    def test_scheduler_failure(self):
        self.fail_command = "scontrol"
        self.assert_not_ready("scheduler")

    def test_empty_or_malformed_scheduler_output_fails_closed(self):
        for output in ("", "garbage", "NodeName=gpu-node", self.node + "\n" + self.node):
            with self.subTest(output=output):
                self.node = output
                self.assert_not_ready("scheduler")

    def test_wrong_host_cannot_attest_compute_runtime_or_cache(self):
        self.node = self.node.replace(socket.gethostname(), "other-node.invalid")
        self.assert_not_ready("local_node")

    def test_partition_must_be_up_and_include_the_selected_node(self):
        self.partition = "PartitionName=gpu State=DOWN"
        self.assert_not_ready("scheduler")
        self.partition = "PartitionName=gpu State=UP"
        self.node = self.node.replace("Partitions=gpu", "Partitions=other")
        self.assert_not_ready("scheduler")

    def test_no_free_gpu_and_unavailable_nodes_fail(self):
        original = self.node
        for state in ("ALLOCATED", "MIXED", "IDLE+DRAIN", "DOWN", "IDLE*"):
            with self.subTest(state=state):
                self.node = original.replace("State=IDLE", "State=" + state)
                self.assert_not_ready("gpu_capacity")
        self.node = original.replace("gres/gpu=2", "gres/gpu=0")
        self.assert_not_ready("gpu_capacity")
        self.node = original.replace("AllocTRES=cpu=0,gres/gpu=0", "AllocTRES=cpu=0,gres/gpu=2")
        self.assert_not_ready("gpu_capacity")

    def test_missing_runtime_or_container_plugin_fails(self):
        self.fail_command = "enroot"
        self.assert_not_ready("container_support")
        self.fail_command = "srun"
        self.assert_not_ready("container_support")

    def test_help_without_pyxis_is_not_container_support(self):
        original = self.run_command
        def plain_help(command, timeout):
            if command == ["srun", "--help"]:
                return 0, "ordinary srun help", ""
            return original(command, timeout)
        with patch.object(self.validator, "run", side_effect=plain_help):
            result = self.validator.validate(self.args)
        self.assertFalse(result["checks"]["container_support"])

    def test_multiple_failure_reasons_are_preserved(self):
        (self.snapshot / "tokenizer.json").unlink()
        self.fail_command = "enroot"
        self.node = self.node.replace("State=IDLE", "State=DOWN")
        result = self.assert_not_ready("cache")
        self.assertTrue({"cache", "container_support", "gpu_capacity"}.issubset({e["stage"] for e in result["errors"]}))

    def test_cache_missing_empty_or_escaping_file_fails(self):
        target = self.snapshot / "model.safetensors"
        target.unlink()
        self.assert_not_ready("cache")
        target.touch()
        self.assert_not_ready("cache")
        target.unlink()
        target.symlink_to("/etc/passwd")
        self.assert_not_ready("cache")

    def test_config_only_cannot_pass_as_a_complete_model(self):
        self.args.require_file = ["config.json"]
        self.assert_not_ready("cache")

    def test_shard_index_requires_every_referenced_weight(self):
        self.args.require_file[-1] = "model.safetensors.index.json"
        index = self.snapshot / "model.safetensors.index.json"
        index.write_text(json.dumps({"weight_map": {"first": "part-1.safetensors", "second": "part-2.safetensors"}}))
        (self.snapshot / "part-1.safetensors").write_bytes(b"first")
        self.assert_not_ready("cache")
        (self.snapshot / "part-2.safetensors").write_bytes(b"second")
        self.assertEqual(self.validate()["status"], "ready")
        for value in ({}, {"weight_map": {}}, {"weight_map": {"x": "../../outside"}}, {"weight_map": {"x": 1}}):
            index.write_text(json.dumps(value))
            self.assert_not_ready("cache")
        index.write_text("invalid json")
        self.assert_not_ready("cache")

    def test_bad_input_is_distinct_and_runs_no_commands(self):
        for field, value in (("container_image", "image:latest"), ("container_image", "image:v1"),
                ("container_image", "--evil@sha256:" + "b" * 64), ("timeout", 0),
                ("timeout", float("nan")), ("timeout", 121), ("node", "n[1-2]"),
                ("node", "--all"), ("partition", "a,b"), ("revision", "main"),
                ("repo_id", "../outside"), ("require_file", []), ("require_file", ["../outside"])):
            with self.subTest(field=field, value=value):
                old = getattr(self.args, field)
                setattr(self.args, field, value)
                self.commands.clear()
                result = self.validate()
                self.assertEqual(result["status"], "bad_input")
                self.assertFalse(result["ok"])
                self.assertEqual(self.commands, [])
                setattr(self.args, field, old)

    def test_optional_probe_is_single_node_single_gpu_pinned_and_bounded(self):
        self.args.gpu_smoke = True
        result = self.validate()
        self.assertTrue(result["gpu_smoke_ran"])
        self.assertTrue(result["gpu_smoke_ok"])
        self.assertFalse(result["training_validated"])
        job = self.commands[-1]
        for arg in ("--nodes=1", "--ntasks=1", "--gpus=1", "--nodelist=gpu-node", "--partition=gpu", "--immediate=5", "--time=1", "--container-image=" + self.args.container_image):
            self.assertIn(arg, job)
        self.assertEqual(job[-3:], ["nvidia-smi", "--query-gpu=index,name", "--format=csv,noheader"])

    def test_optional_probe_is_not_run_after_preflight_failure(self):
        self.args.gpu_smoke = True
        self.fail_command = "enroot"
        result = self.assert_not_ready("container_support")
        self.assertFalse(result["gpu_smoke_ran"])
        self.assertFalse(any("--gpus=1" in c for c in self.commands))

    def test_optional_probe_empty_output_or_multiple_gpus_is_failure(self):
        self.args.gpu_smoke = True
        for output in ("", "0, GPU\n1, GPU", "garbage"):
            self.smoke_output = output
            self.assert_not_ready("gpu_smoke")

    def test_command_failures_are_safe(self):
        for exception in (FileNotFoundError(), PermissionError(), subprocess.TimeoutExpired("private", 5)):
            with patch.object(self.validator.subprocess, "run", side_effect=exception):
                rc, out, err = self.validator.run(["missing"], timeout=1)
            self.assertNotEqual(rc, 0)
            self.assertNotIn("private", out + err)

    def test_cli_ready_and_not_ready_exit_codes_with_inert_commands(self):
        # Run the actual CLI without any path to real Slurm/Enroot executables.
        tools = self.cache / "bin"
        tools.mkdir()
        outputs = {"scontrol": self.node, "enroot": "3.5.0", "srun": "--container-image --container-mounts"}
        for name, output in outputs.items():
            path = tools / name
            path.write_text("#!" + sys.executable + "\nimport sys\n"
                + "print(" + repr(self.partition) + " if 'partition' in sys.argv else " + repr(output) + ")\n")
            path.chmod(0o755)
        command = [sys.executable, str(SCRIPT), "--json"]
        for field in ("cache_dir", "repo_id", "revision", "node", "partition", "container_image"):
            command += ["--" + field.replace("_", "-"), getattr(self.args, field)]
        for name in self.args.require_file:
            command += ["--require-file", name]
        for expected in (0, 1):
            proc = subprocess.run(command, env={"PATH": str(tools)}, capture_output=True, text=True, timeout=10)
            self.assertEqual(proc.returncode, expected, proc.stderr)
            result = json.loads(proc.stdout)
            self.assertEqual(result["status"], "ready" if expected == 0 else "not_ready")
            self.assertFalse(result["training_validated"])
            (self.snapshot / "model.safetensors").write_bytes(b"")

    def test_optional_probe_nonzero_status_is_failure(self):
        self.args.gpu_smoke = True
        original = self.run_command
        def failed_job(command, timeout):
            if "--gpus=1" in command:
                return 1, "private output", "private failure"
            return original(command, timeout)
        with patch.object(self.validator, "run", side_effect=failed_job):
            result = self.validator.validate(self.args)
        self.assertEqual(result["status"], "not_ready")
        self.assertTrue(result["gpu_smoke_ran"])
        self.assertFalse(result["gpu_smoke_ok"])
        self.assertNotIn("private", json.dumps(result))

    def test_cli_usage_error_returns_json_and_exit_two(self):
        proc = subprocess.run([sys.executable, str(SCRIPT), "--json", "--nodes", "2"],
                              capture_output=True, text=True, timeout=10)
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(json.loads(proc.stdout)["status"], "bad_input")


if __name__ == "__main__":
    unittest.main()
