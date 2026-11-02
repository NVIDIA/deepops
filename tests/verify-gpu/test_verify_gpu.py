#!/usr/bin/env python3
"""Inert verify_gpu.sh regressions: python3 tests/verify-gpu/test_verify_gpu.py.

Only kubectl is replaced; the real script and common.sh run in a disposable
checkout fragment, so neither the cluster nor the source manifest is modified.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("DEEPOPS_TEST_ROOT", Path(__file__).resolve().parents[2]))


class VerifyGPU(unittest.TestCase):
    def run_script(self, capacities):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("scripts/k8s/verify_gpu.sh", "scripts/common.sh",
                         "workloads/examples/k8s/cluster-gpu-test-job.yml"):
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            manifest = root / "workloads/examples/k8s/cluster-gpu-test-job.yml"
            original = manifest.read_text()
            binary = root / "bin"
            binary.mkdir()
            mock = binary / "kubectl"
            mock.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$CALLS"
case "$*" in
  'describe nodes') printf '%s' "$CAPACITY" ;;
  *' get pods')
    for ((i=0; i<${PODS}; i++)); do
      echo "cluster-gpu-tests-$i 0/1 Completed 0 1m"
    done ;;
  *' logs -f '*) echo 'GPU test output' ;;
esac
''')
            mock.chmod(0o755)
            capacity = "".join(
                "Name: fixture-node\nCapacity:\n cpu: 8\n memory: 32Gi\n"
                + ("" if value is None else f" nvidia.com/gpu: {value}\n")
                + " pods: 110\nAllocatable:\n cpu: 8\n\n"
                for value in capacities
            )
            env = {**os.environ, "PATH": f"{binary}:/usr/bin:/bin",
                   "CALLS": str(root / "calls"), "CAPACITY": capacity,
                   "PODS": str(sum(value or 0 for value in capacities)),
                   "DEEPOPS_CONFIG_DIR": str(root / "absent-config"),
                   "DEEPOPS_VERSION": "test", "CLUSTER_VERIFY_EXPECTED_PODS": "",
                   "CLUSTER_VERIFY_NS": "fixture-gpu-verify",
                   "CLUSTER_VERIFY_JOB": str(manifest),
                   "TESTS_DIR": str(manifest.parent)}
            result = subprocess.run(["bash", str(root / "scripts/k8s/verify_gpu.sh")],
                                    env=env, text=True, capture_output=True, timeout=10)
            return result, (root / "calls").read_text().splitlines(), original, manifest.read_text()

    def test_zero_capacity_does_not_mutate_cluster_or_manifest(self):
        for capacities in ([], [None], [0], [None, 0, 0]):
            with self.subTest(capacities=capacities):
                result, calls, before, after = self.run_script(capacities)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("nvidia.com/gpu", result.stdout + result.stderr)
                self.assertEqual(calls, ["describe nodes"])
                self.assertEqual(before, after)

    def test_positive_capacity_keeps_existing_job_flow(self):
        for capacities, count in (([1], 1), ([None, 2, 1], 3)):
            with self.subTest(capacities=capacities):
                result, calls, _, manifest = self.run_script(capacities)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"parallelism: {count} # DYNAMIC_PARALLELISM", manifest)
                self.assertIn(f"completions: {count} # DYNAMIC_COMPLETIONS", manifest)
                self.assertIn(f"{count} / {count} GPU Jobs COMPLETED", result.stdout)
                self.assertTrue(any("create -f" in call for call in calls))
                self.assertEqual(calls[-1], "delete ns fixture-gpu-verify")


if __name__ == "__main__":
    unittest.main()
