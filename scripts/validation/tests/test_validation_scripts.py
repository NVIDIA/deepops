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

    def test_node_details_are_unique_normalized_and_sorted(self):
        states = "node-b down*\nnode-a IDLE+\nnode-b idle\n"
        gres = "node-b gpu:h100:8(S:0-1)\nnode-a gpu:2\nnode-b gpu:4\n"
        self.assertEqual(
            validate_slurm.build_node_details(states, gres),
            [
                {"name": "node-a", "state": "idle", "gpus_configured": 2},
                {"name": "node-b", "state": "down", "gpus_configured": 8},
            ],
        )

    def test_node_details_default_missing_gres_to_zero(self):
        self.assertEqual(
            validate_slurm.build_node_details("node1 mixed\n", ""),
            [{"name": "node1", "state": "mixed", "gpus_configured": 0}],
        )


class TestK8sParsers(unittest.TestCase):
    def test_summarize_nodes(self):
        doc = {
            "items": [
                {
                    "metadata": {"name": "node-a"},
                    "status": {
                        "conditions": [{"type": "Ready", "status": "True"}],
                        "allocatable": {"nvidia.com/gpu": "8"},
                    }
                },
                {
                    "metadata": {"name": "node-b"},
                    "status": {
                        "conditions": [{"type": "Ready", "status": "False"}],
                        "allocatable": {},
                    }
                },
            ]
        }
        total, ready, gpus, nodes = validate_k8s.summarize_nodes(doc)
        self.assertEqual((total, ready, gpus), (2, 1, 8))
        self.assertEqual(
            nodes,
            [
                {"name": "node-a", "ready": True, "gpus_allocatable": 8},
                {"name": "node-b", "ready": False, "gpus_allocatable": 0},
            ],
        )

    def test_summarize_nodes_details_are_sorted_and_malformed_gpus_are_zero(self):
        doc = {
            "items": [
                {
                    "metadata": {"name": "node-b"},
                    "status": {
                        "conditions": [{"type": "Ready", "status": "False"}],
                        "allocatable": {"nvidia.com/gpu": None},
                    },
                },
                {
                    "metadata": {"name": "node-a"},
                    "status": {
                        "conditions": [{"type": "Ready", "status": "True"}],
                        "allocatable": {"nvidia.com/gpu": "not-a-count"},
                    },
                },
                {
                    "metadata": {"name": "node-c"},
                    "status": {
                        "conditions": [{"type": "Ready", "status": "True"}],
                        "allocatable": {"nvidia.com/gpu": "4"},
                    },
                },
            ]
        }
        total, ready, gpus, nodes = validate_k8s.summarize_nodes(doc)
        self.assertEqual((total, ready, gpus), (3, 2, 4))
        self.assertEqual(
            nodes,
            [
                {"name": "node-a", "ready": True, "gpus_allocatable": 0},
                {"name": "node-b", "ready": False, "gpus_allocatable": 0},
                {"name": "node-c", "ready": True, "gpus_allocatable": 4},
            ],
        )

    def test_parse_gpu_count_rejects_other_malformed_values(self):
        for value in (True, -1, "-2", 1.5, [], {}):
            with self.subTest(value=value):
                self.assertEqual(validate_k8s.parse_gpu_count(value), 0)

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


def inventory(**groups):
    """Build an ``ansible-inventory --list`` document from group -> hosts/children."""
    doc = {"_meta": {"hostvars": {}}, "all": {"children": list(groups)}}
    for name, spec in groups.items():
        hosts = spec.get("hosts", [])
        doc[name] = {"hosts": hosts, "children": spec.get("children", [])}
        for h in hosts:
            doc["_meta"]["hostvars"][h] = {}
    return doc


class TestDoctorTopology(unittest.TestCase):
    def test_example_slurm_layout_passes(self):
        doc = inventory(
            **{
                "slurm-master": {"hosts": ["mgmt01"]},
                "slurm-node": {"hosts": ["gpu01", "gpu02"]},
                "slurm-login": {"children": ["slurm-master"]},
                "slurm-cluster": {"children": ["slurm-master", "slurm-node", "slurm-login"]},
            }
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertTrue(ok, detail)
        self.assertIn("slurm: 1 master, 2 node", detail)
        self.assertIn("kubernetes: 0 control-plane, 0 etcd, 0 node", detail)

    def test_example_k8s_layout_passes(self):
        doc = inventory(
            kube_control_plane={"hosts": ["mgmt01"]},
            etcd={"hosts": ["mgmt01"]},
            kube_node={"hosts": ["mgmt01", "gpu01"]},
            k8s_cluster={"children": ["kube_control_plane", "kube_node"]},
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertTrue(ok, detail)
        self.assertIn("kubernetes: 1 control-plane, 1 etcd, 2 node", detail)

    def test_resolve_group_hosts_follows_children_and_tolerates_cycles(self):
        doc = inventory(
            a={"hosts": ["h1"], "children": ["b"]},
            b={"hosts": ["h2"], "children": ["a"]},
        )
        self.assertEqual(deepops_doctor.resolve_group_hosts(doc, "a"), {"h1", "h2"})
        self.assertEqual(deepops_doctor.resolve_group_hosts(doc, "missing"), set())

    def test_slurm_node_without_master_fails(self):
        doc = inventory(
            **{
                "slurm-node": {"hosts": ["gpu01"]},
                "slurm-cluster": {"children": ["slurm-node"]},
            }
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("Slurm group 'slurm-master' is empty", detail)

    def test_slurm_hosts_outside_umbrella_fail(self):
        doc = inventory(
            **{
                "slurm-master": {"hosts": ["mgmt01"]},
                "slurm-node": {"hosts": ["gpu01", "gpu02"]},
                "slurm-cluster": {"children": ["slurm-master"]},
            }
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("2 Slurm host(s) not in 'slurm-cluster'", detail)
        self.assertIn("gpu01, gpu02", detail)

    def test_k8s_without_etcd_fails(self):
        doc = inventory(
            kube_control_plane={"hosts": ["mgmt01"]},
            kube_node={"hosts": ["gpu01"]},
            k8s_cluster={"children": ["kube_control_plane", "kube_node"]},
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("Kubernetes group 'etcd' is empty", detail)

    def test_misspelled_group_fails(self):
        doc = inventory(
            **{
                "slurm_master": {"hosts": ["mgmt01"]},
                "slurm-node": {"hosts": ["gpu01"]},
                "slurm-cluster": {"children": ["slurm_master", "slurm-node"]},
            }
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("'slurm_master' looks like a misspelling of 'slurm-master'", detail)
        self.assertIn("Slurm group 'slurm-master' is empty", detail)

    def test_legacy_kube_master_name_fails(self):
        doc = inventory(
            **{
                "kube-master": {"hosts": ["mgmt01"]},
                "etcd": {"hosts": ["mgmt01"]},
                "kube_node": {"hosts": ["gpu01"]},
                "k8s_cluster": {"children": ["kube-master", "kube_node"]},
            }
        )
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("'kube-master' looks like a misspelling of 'kube_control_plane'", detail)

    def test_hosts_but_no_cluster_groups_fails(self):
        doc = inventory(gpus={"hosts": ["gpu01", "gpu02"]})
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertFalse(ok)
        self.assertIn("no hosts in slurm-master/slurm-node or", detail)

    def test_stray_and_mixed_hosts_are_notes_not_failures(self):
        doc = inventory(
            **{
                "slurm-master": {"hosts": ["mgmt01"]},
                "slurm-node": {"hosts": ["gpu01"]},
                "slurm-cluster": {"children": ["slurm-master", "slurm-node"]},
                "kube_control_plane": {"hosts": ["mgmt01"]},
                "etcd": {"hosts": ["mgmt01"]},
                "kube_node": {"hosts": ["gpu01"]},
                "k8s_cluster": {"children": ["kube_control_plane", "kube_node"]},
                "storage": {"hosts": ["nfs01"]},
            }
        )
        doc["ungrouped"] = {"hosts": ["spare01"]}
        doc["_meta"]["hostvars"]["spare01"] = {}
        ok, detail = deepops_doctor.check_inventory_topology(doc)
        self.assertTrue(ok, detail)
        self.assertIn("2 host(s) in no cluster group: nfs01, spare01", detail)
        self.assertIn("1 host(s) in both slurm-node and kube_node: gpu01", detail)


if __name__ == "__main__":
    unittest.main()
