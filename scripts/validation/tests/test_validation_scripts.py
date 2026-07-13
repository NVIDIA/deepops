"""Unit tests for the validation script parsers (standard library only).

Run with: python3 -m unittest discover scripts/validation/tests
"""

import importlib.util
import os
import unittest

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(SCRIPTS_DIR, name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validate_slurm = load("validate_slurm")
validate_k8s = load("validate_k8s")
deepops_doctor = load("deepops_doctor")


class TestSlurmParsers(unittest.TestCase):
    def test_sinfo_states_healthy(self):
        out = "node1 idle\nnode2 mixed\nnode3 allocated\n"
        total, avail, unavail, states = validate_slurm.parse_sinfo_states(out)
        self.assertEqual((total, avail, unavail), (3, 3, 0))
        self.assertEqual(states["idle"], 1)

    def test_sinfo_states_down_and_flags(self):
        out = "node1 idle\nnode2 down*\nnode3 drained\n"
        total, avail, unavail, states = validate_slurm.parse_sinfo_states(out)
        self.assertEqual((total, avail, unavail), (3, 1, 2))
        self.assertIn("down", states)
        self.assertIn("drained", states)

    def test_sinfo_states_dedupes_partition_overlap(self):
        out = "node1 idle\nnode1 idle\n"
        total, _, _, _ = validate_slurm.parse_sinfo_states(out)
        self.assertEqual(total, 1)

    def test_gres_gpu_totals(self):
        out = "node1 gpu:4\nnode2 gpu:h100:8(S:0-1)\nnode3 (null)\n"
        self.assertEqual(validate_slurm.parse_gres_gpus(out), 12)

    def test_gres_dedupes_nodes(self):
        out = "node1 gpu:4\nnode1 gpu:4\n"
        self.assertEqual(validate_slurm.parse_gres_gpus(out), 4)


class TestK8sParsers(unittest.TestCase):
    def test_summarize_nodes(self):
        doc = {
            "items": [
                {
                    "status": {
                        "conditions": [{"type": "Ready", "status": "True"}],
                        "allocatable": {"nvidia.com/gpu": "8"},
                    }
                },
                {
                    "status": {
                        "conditions": [{"type": "Ready", "status": "False"}],
                        "allocatable": {},
                    }
                },
            ]
        }
        total, ready, gpus = validate_k8s.summarize_nodes(doc)
        self.assertEqual((total, ready, gpus), (2, 1, 8))

    def test_summarize_gpu_pods(self):
        doc = {
            "items": [
                {
                    "status": {
                        "phase": "Running",
                        "containerStatuses": [{"ready": True}],
                    }
                },
                {
                    "status": {
                        "phase": "Running",
                        "containerStatuses": [{"ready": False}],
                    }
                },
                {"status": {"phase": "Succeeded"}},
                {"status": {"phase": "Pending"}},
            ]
        }
        total, ready = validate_k8s.summarize_gpu_pods(doc)
        self.assertEqual((total, ready), (4, 2))

    def test_smoke_pod_manifest_requests_one_gpu(self):
        pod = validate_k8s.smoke_pod_manifest("example/image:tag")
        limits = pod["spec"]["containers"][0]["resources"]["limits"]
        self.assertEqual(limits["nvidia.com/gpu"], 1)


class TestDoctorParsers(unittest.TestCase):
    def test_count_inventory_hosts(self):
        doc = {
            "_meta": {"hostvars": {"n1": {}, "n2": {}}},
            "all": {"children": ["slurm-master"]},
            "slurm-master": {"hosts": ["n1"]},
            "slurm-node": {"hosts": ["n2"]},
        }
        hosts, groups = deepops_doctor.count_inventory_hosts(doc)
        self.assertEqual(hosts, 2)
        self.assertIn("slurm-node", groups)

    def test_count_positive_stdout_hosts(self):
        out = (
            "n1 | CHANGED | rc=0 | (stdout) 2\n"
            "n2 | CHANGED | rc=0 | (stdout) 0\n"
            "n3 | CHANGED | rc=0 | (stdout) not-a-number\n"
        )
        self.assertEqual(deepops_doctor.count_positive_stdout_hosts(out), 1)


if __name__ == "__main__":
    unittest.main()
