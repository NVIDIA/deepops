"""Offline tests for validate_runai.py (standard library only).

Run with: python3 -m unittest discover scripts/validation/tests
A fake Kube object replaces kubectl, so no cluster is needed. These prove the
verdict logic; they do not prove a real GPU job ran (that needs a live run).
"""

import importlib.util
import json
import os
import unittest

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "validate_runai", os.path.join(SCRIPTS_DIR, "validate_runai.py"))
vr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vr)


def deploy(name, want=1, have=1):
    return {"metadata": {"name": name}, "spec": {"replicas": want}, "status": {"availableReplicas": have}}


HEALTHY = {"items": [deploy(n) for n in
                     ("kai-operator", "binder", "queue-controller", "admission", "kai-scheduler-default", "runai-scheduler-default")]}


def pod(name, node="n1", group="g1", pg="pg-" + "x"):
    return {"metadata": {"name": name, "labels": {"runai-gpu-group": group} if group else {},
                         "annotations": {"pod-group-name": pg} if pg else {}},
            "spec": {"nodeName": node}}


class FakeKube:
    """Scripted stand-in for the Kube wrapper."""

    def __init__(self, deployments=HEALTHY, crd=True, pods=None, phases=None, logs=None,
                 apply_rc=0, ns_rc=0, namespaces=None, nodes=True):
        self.deployments, self.crd, self.pods = deployments, crd, pods or {}
        self.phases, self.logged, self.apply_rc, self.ns_rc = phases or {}, logs or {}, apply_rc, ns_rc
        self.namespaces, self.nodes = namespaces or {"items": []}, nodes
        self.applied, self.deleted = [], []

    def get_json(self, args, timeout=60):
        if args[:2] == ["get", "nodes"]:
            return ({"items": [{}]}, "") if self.nodes else (None, "refused")
        if args[:2] == ["get", "namespaces"]:
            return self.namespaces, ""
        if "deployments" in args:
            return (self.deployments, "") if self.deployments is not None else (None, "forbidden")
        if "crd" in args:
            return ({}, "") if self.crd else (None, "not found")
        if "pod" in args:
            return self.pods.get(args[-1], {}), ""
        return None, "unexpected %s" % args

    def apply(self, manifest):
        self.applied.append(manifest)
        return self.apply_rc, "", "denied" if self.apply_rc else ""

    def wait_phase(self, namespace, pod_name, phases, timeout):
        return self.phases.get(pod_name, "Succeeded")

    def logs(self, namespace, pod_name):
        return self.logged.get(pod_name, "GPU 0: Test GPU (UUID: x)")

    def ensure_namespace(self, namespace):
        return self.ns_rc, "", ""

    def delete_namespace(self, namespace):
        self.deleted.append(namespace)


def args(*extra):
    # tests never really wait; the wait has its own tests below
    extra = list(extra)
    if "--ready-timeout" not in extra:
        extra += ["--ready-timeout", "0"]
    return vr.parse_args(extra)


GOOD_PODS = {"kai-whole-gpu": pod("kai-whole-gpu"), "kai-half-a": pod("kai-half-a"),
             "kai-half-b": pod("kai-half-b")}


class TestParsers(unittest.TestCase):
    def test_deployments_flag_unavailable(self):
        names, bad = vr.summarize_deployments({"items": [deploy("binder", 1, 0), deploy("x", 0, 0)]})
        self.assertEqual(names, ["binder", "x"])
        self.assertEqual(bad, ["binder (0/1 available)"])

    def test_missing_deployments_needs_a_scheduler_shard(self):
        self.assertEqual(vr.missing_deployments(["kai-operator", "binder", "queue-controller", "admission"]),
                         ["kai-scheduler-<shard>"])
        self.assertEqual(vr.missing_deployments(list(vr.REQUIRED_DEPLOYMENTS) + ["kai-scheduler-default"]), [])

    def test_same_gpu_requires_node_and_group(self):
        self.assertTrue(vr.same_gpu([("n1", "g", "p"), ("n1", "g", "p")]))
        self.assertFalse(vr.same_gpu([("n1", "g", "p"), ("n1", "h", "p")]))
        self.assertFalse(vr.same_gpu([("n1", "g", "p"), ("n2", "g", "p")]))
        self.assertFalse(vr.same_gpu([("n1", "", "p"), ("n1", "", "p")]))
        self.assertFalse(vr.same_gpu([("", "g", "p"), ("", "g", "p")]))
        self.assertFalse(vr.same_gpu([("n1", "g", "p")]))

    def test_leftovers(self):
        ns = {"items": [{"metadata": {"name": n}} for n in
                        ("default", "kai-scheduler", "runai", "runai-backend", "kai-resource-reservation", "runaix-ok")]}
        rel = [{"name": "kai-scheduler", "namespace": "kai-scheduler", "chart": "kai-scheduler-v0.18.5"},
               {"name": "gpu", "namespace": "g", "chart": "gpu-operator-v26.7.0"}]
        found = vr.leftovers(ns, rel)
        self.assertIn("namespace/runai", found)
        self.assertIn("namespace/runai-backend", found)
        self.assertIn("namespace/kai-resource-reservation", found)
        self.assertIn("release/kai-scheduler/kai-scheduler", found)
        self.assertNotIn("namespace/default", found)
        self.assertFalse([f for f in found if "gpu-operator" in f or "/gpu" in f])
        self.assertEqual(vr.leftovers({"items": []}, []), [])

    def test_cluster_connected(self):
        doc = {"clusters": [{"name": "deepops", "status": {"platform": "Connected"}}]}
        self.assertEqual(vr.cluster_connected(doc, "deepops"), (True, True))
        doc["clusters"][0]["status"]["platform"] = "WaitingToConnect"
        self.assertEqual(vr.cluster_connected(doc, "deepops"), (True, False))
        self.assertEqual(vr.cluster_connected([], "deepops"), (False, False))

    def test_pod_manifest_uses_kai_and_queue(self):
        m = vr.pod_manifest("p", "ns", "img", ["a"], [], "kai-scheduler", "kai.scheduler/queue", "q",
                            gpu_limit=1, annotations={"gpu-fraction": "0.5"})
        self.assertEqual(m["spec"]["schedulerName"], "kai-scheduler")
        self.assertEqual(m["metadata"]["labels"], {"kai.scheduler/queue": "q"})
        self.assertEqual(m["spec"]["containers"][0]["resources"]["limits"]["nvidia.com/gpu"], 1)
        self.assertFalse(m["spec"]["automountServiceAccountToken"])


class TestVerdict(unittest.TestCase):
    def test_all_good_is_ok_and_cleans_up(self):
        kube = FakeKube(pods=GOOD_PODS)
        result = vr.validate(args(), {}, kube)
        self.assertTrue(result["ok"], result["failures"])
        self.assertTrue(result["gpu_job_ok"] and result["fraction_job_ok"])
        self.assertEqual(kube.deleted, ["deepops-runai-validate"])
        self.assertEqual(json.loads(json.dumps(result))["schema_version"], 1)
        # the two fractional pods ask for half a GPU and must not also ask for a whole one
        halves = [m for m in kube.applied if m["metadata"]["name"].startswith("kai-half")]
        self.assertEqual(len(halves), 2)
        for m in halves:
            self.assertEqual(m["metadata"]["annotations"]["gpu-fraction"], "0.5")
            self.assertNotIn("resources", m["spec"]["containers"][0])

    def test_no_cluster_is_not_ok(self):
        result = vr.validate(args(), {}, FakeKube(nodes=False))
        self.assertFalse(result["ok"])
        self.assertFalse(result["api_reachable"])

    def test_unready_scheduler_is_not_ok(self):
        bad = {"items": [deploy("kai-operator", 1, 0)] + HEALTHY["items"][1:]}
        result = vr.validate(args(), {}, FakeKube(deployments=bad, pods=GOOD_PODS))
        self.assertFalse(result["ok"])
        self.assertFalse(result["gpu_job_ran"])  # does not run jobs on a broken scheduler

    def test_missing_queue_crd_is_not_ok(self):
        result = vr.validate(args(), {}, FakeKube(crd=False, pods=GOOD_PODS))
        self.assertFalse(result["ok"])

    def test_whole_gpu_failure(self):
        kube = FakeKube(pods=GOOD_PODS, phases={"kai-whole-gpu": "Failed"})
        result = vr.validate(args(), {}, kube)
        self.assertFalse(result["ok"])
        self.assertIn("namespace deepops-runai-validate kept for debugging", result["failures"])
        self.assertEqual(kube.deleted, [])

    def test_whole_gpu_without_a_kai_pod_group_is_not_ok(self):
        pods = dict(GOOD_PODS, **{"kai-whole-gpu": pod("kai-whole-gpu", pg=None)})
        result = vr.validate(args(), {}, FakeKube(pods=pods))
        self.assertFalse(result["gpu_job_ok"])
        self.assertFalse(result["ok"])

    def test_default_scheduler_pod_is_not_proof(self):
        # nvidia-smi worked but KAI never grouped the pod: it was not scheduled by KAI
        pods = dict(GOOD_PODS, **{"kai-whole-gpu": pod("kai-whole-gpu", group="", pg=None)})
        self.assertFalse(vr.validate(args(), {}, FakeKube(pods=pods))["ok"])

    def test_halves_on_different_gpus_is_not_ok(self):
        pods = dict(GOOD_PODS, **{"kai-half-b": pod("kai-half-b", group="g2")})
        result = vr.validate(args(), {}, FakeKube(pods=pods))
        self.assertFalse(result["fraction_job_ok"])
        self.assertFalse(result["ok"])

    def test_halves_that_never_start_is_not_ok(self):
        result = vr.validate(args(), {}, FakeKube(pods=GOOD_PODS, phases={"kai-half-b": "Pending"}))
        self.assertFalse(result["ok"])

    def test_pod_without_gpu_output_is_not_ok(self):
        kube = FakeKube(pods=GOOD_PODS, logs={"kai-whole-gpu": "no devices"})
        self.assertFalse(vr.validate(args(), {}, kube)["ok"])

    def test_apply_failure_is_not_ok(self):
        self.assertFalse(vr.validate(args(), {}, FakeKube(apply_rc=1, pods=GOOD_PODS))["ok"])

    def test_namespace_failure_is_not_ok(self):
        self.assertFalse(vr.validate(args(), {}, FakeKube(ns_rc=1, pods=GOOD_PODS))["ok"])

    def test_skip_gpu_jobs_is_scheduler_only(self):
        result = vr.validate(args("--skip-gpu-jobs"), {}, FakeKube())
        self.assertTrue(result["ok"])
        self.assertFalse(result["gpu_job_ran"])


class TestMemoryEnforcement(unittest.TestCase):
    def pods(self):
        return dict(GOOD_PODS)

    def test_inside_ok_and_outside_refused_is_ok(self):
        kube = FakeKube(pods=self.pods(), phases={"kai-mem-outside": "Failed"},
                        logs={"kai-mem-inside": "ALLOC_OK 256", "kai-mem-outside": "ALLOC_FAILED alloc rc=2"})
        result = vr.validate(args("--memory-enforcement"), {}, kube)
        self.assertTrue(result["ok"], result["failures"])
        self.assertTrue(result["memory_enforcement_ok"])
        outside = [m for m in kube.applied if m["metadata"]["name"] == "kai-mem-outside"][0]
        self.assertEqual(outside["metadata"]["annotations"][
            "nvidia.com/container.gpu-workload.gpu-memory.limit"], "1024Mi")

    def test_outside_allowed_to_allocate_is_not_ok(self):
        kube = FakeKube(pods=self.pods(),
                        logs={"kai-mem-inside": "ALLOC_OK 256", "kai-mem-outside": "ALLOC_OK 4096"})
        result = vr.validate(args("--memory-enforcement"), {}, kube)
        self.assertFalse(result["ok"])
        self.assertFalse(result["memory_enforcement_ok"])

    def test_outside_killed_for_another_reason_is_not_proof(self):
        kube = FakeKube(pods=self.pods(), phases={"kai-mem-outside": "Failed"},
                        logs={"kai-mem-inside": "ALLOC_OK 256", "kai-mem-outside": "ImportError"})
        self.assertFalse(vr.validate(args("--memory-enforcement"), {}, kube)["ok"])

    def test_inside_failing_is_not_ok(self):
        kube = FakeKube(pods=self.pods(), phases={"kai-mem-inside": "Failed"},
                        logs={"kai-mem-inside": "ALLOC_FAILED alloc rc=2"})
        self.assertFalse(vr.validate(args("--memory-enforcement"), {}, kube)["ok"])

    def test_off_by_default(self):
        result = vr.validate(args(), {}, FakeKube(pods=GOOD_PODS))
        self.assertFalse(result["memory_enforcement_ran"])


class TestPlatformAndUninstall(unittest.TestCase):
    def test_platform_needs_a_domain(self):
        with self.assertRaises(SystemExit):
            args("--mode", "platform")

    def test_platform_without_credentials_is_not_ok(self):
        orig = vr.https_request
        vr.https_request = lambda *a, **k: (200, b"")
        try:
            result = vr.validate(args("--mode", "platform", "--platform-domain", "runai.lab.test"),
                                 {}, FakeKube(pods=GOOD_PODS))
        finally:
            vr.https_request = orig
        self.assertFalse(result["ok"])
        self.assertTrue(result["platform_api_ok"])
        self.assertFalse(result["platform_cluster_connected"])
        self.assertTrue(any("RUNAI_USERNAME" in f for f in result["failures"]))

    def _platform(self, clusters_status):
        calls = []

        def fake(domain, ip, ca, method, path, body=None, headers=None, timeout=20):
            calls.append((method, path))
            if path == "/":
                return 200, b"<html>"
            if path == "/api/v2/token":
                return 200, json.dumps({"access_token": "t"}).encode()
            if path == "/api/v1/clusters":
                return 200, json.dumps({"clusters": [{"name": "deepops", "status": {"platform": clusters_status}}]}).encode()
            return 404, b""
        orig = vr.https_request
        vr.https_request = fake
        try:
            result = vr.validate(args("--mode", "platform", "--platform-domain", "runai.lab.test"),
                                 {"RUNAI_USERNAME": "u", "RUNAI_PASSWORD": "p"}, FakeKube(pods=GOOD_PODS))
        finally:
            vr.https_request = orig
        return result

    def test_platform_connected_is_ok(self):
        result = self._platform("Connected")
        self.assertTrue(result["ok"], result["failures"])
        self.assertTrue(result["platform_cluster_connected"])

    def test_platform_waiting_is_not_ok(self):
        result = self._platform("WaitingToConnect")
        self.assertFalse(result["ok"])

    def test_platform_credentials_never_in_output(self):
        self.assertNotIn('"p"', json.dumps(self._platform("Connected")))

    def test_uninstalled_clean(self):
        orig = vr.run
        vr.run = lambda cmd, timeout=60, input_text=None: (0, "[]", "")
        try:
            result = vr.validate(args("--verify-uninstalled"), {}, FakeKube())
        finally:
            vr.run = orig
        self.assertTrue(result["ok"], result["failures"])
        self.assertTrue(result["uninstalled_ok"])
        self.assertEqual(result["mode"], "uninstalled")

    def test_uninstalled_finds_leftovers(self):
        orig = vr.run
        vr.run = lambda cmd, timeout=60, input_text=None: (0, "[]", "")
        try:
            ns = {"items": [{"metadata": {"name": "runai"}}]}
            result = vr.validate(args("--verify-uninstalled"), {}, FakeKube(namespaces=ns))
        finally:
            vr.run = orig
        self.assertFalse(result["ok"])
        self.assertEqual(result["leftovers"], ["namespace/runai"])


class TestPlatformProject(unittest.TestCase):
    def _run(self, create_status=201, delete_status=200):
        calls = []

        def fake(domain, ip, ca, method, path, body=None, headers=None, timeout=20):
            calls.append((method, path, body))
            if path == "/":
                return 200, b"<html>"
            if path == "/api/v2/token":
                return 200, json.dumps({"access_token": "t"}).encode()
            if path == "/api/v1/clusters":
                return 200, json.dumps({"clusters": [{"name": "deepops", "uuid": "c1",
                                                      "status": {"platform": "Connected"}}]}).encode()
            if path == "/api/v1/node-pools":
                return 200, json.dumps({"nodepools": [{"id": 7, "name": "default", "clusterId": "c1"}]}).encode()
            if path == "/api/v1/org-unit/projects" and method == "POST":
                return create_status, json.dumps({"id": "p1"}).encode()
            if path == "/api/v1/org-unit/projects/p1" and method == "DELETE":
                return delete_status, b""
            return 404, b""
        orig = vr.https_request
        vr.https_request = fake
        kube = FakeKube(pods={"kai-whole-gpu": pod("kai-whole-gpu"), "kai-half-a": pod("kai-half-a"),
                              "kai-half-b": pod("kai-half-b")})
        kube_get = kube.get_json
        kube.get_json = lambda a, timeout=60: ({}, "") if a[:2] == ["get", "namespace"] else kube_get(a, timeout)
        try:
            result = vr.validate(args("--mode", "platform", "--platform-domain", "runai.lab.test",
                                      "--create-project", "dv"),
                                 {"RUNAI_USERNAME": "u", "RUNAI_PASSWORD": "p"}, kube)
        finally:
            vr.https_request = orig
        return result, calls, kube

    def test_project_created_used_and_deleted(self):
        result, calls, kube = self._run()
        self.assertTrue(result["ok"], result["failures"])
        self.assertTrue(result["project_created"] and result["project_deleted"])
        self.assertEqual([m for m, p, _ in calls if p.startswith("/api/v1/org-unit")], ["POST", "DELETE"])
        self.assertEqual(kube.applied[0]["metadata"]["namespace"], "runai-dv")
        self.assertEqual(kube.applied[0]["spec"]["schedulerName"], "runai-scheduler")
        self.assertEqual(kube.applied[0]["metadata"]["labels"], {"runai/queue": "dv", "kai.scheduler/queue": "dv"})

    def test_create_body_shape(self):
        body = vr.project_body("dv", "c1", "7", 1)
        self.assertEqual(body["resources"][0]["nodePool"], {"id": "7"})
        self.assertEqual(body["resources"][0]["gpu"]["deserved"], 1)

    def test_create_failure_is_not_ok(self):
        result, _, _ = self._run(create_status=400)
        self.assertFalse(result["ok"])

    def test_delete_failure_is_not_ok(self):
        result, _, _ = self._run(delete_status=500)
        self.assertFalse(result["ok"])

    def test_create_project_needs_platform_mode(self):
        with self.assertRaises(SystemExit):
            args("--create-project", "dv")


class TestReadyWait(unittest.TestCase):
    def test_waits_until_scheduler_is_up(self):
        bad = {"items": [deploy("binder", 1, 0)]}
        kube = FakeKube(deployments=bad)
        seq = iter([bad, bad, HEALTHY])
        orig = kube.get_json

        def get_json(a, timeout=60):
            if a[-1] == "deployments":
                return next(seq, HEALTHY), ""
            return orig(a, timeout)
        kube.get_json = get_json
        sleeps = []
        ok = vr.wait_until_ready(kube, args("--ready-timeout", "300"), {}, sleep=sleeps.append, now=lambda: 0)
        self.assertTrue(ok)
        self.assertEqual(len(sleeps), 2)

    def test_gives_up_at_the_deadline(self):
        kube = FakeKube(deployments={"items": [deploy("binder", 1, 0)]})
        clock = iter(range(0, 10000, 100))
        ok = vr.wait_until_ready(kube, args("--ready-timeout", "250"), {}, sleep=lambda s: None,
                                 now=lambda: next(clock))
        self.assertFalse(ok)

    def test_default_is_off_for_kai_and_on_for_platform(self):
        self.assertIsNone(vr.parse_args([]).ready_timeout)
        r = vr.validate(args(), {}, FakeKube(pods=GOOD_PODS))
        self.assertTrue(r["ok"], r["failures"])


class TestPlatformNames(unittest.TestCase):
    def test_platform_scheduler_is_runai_scheduler(self):
        a = args("--mode", "platform", "--platform-domain", "runai.lab.test")
        self.assertEqual(a.scheduler_name, "runai-scheduler")
        self.assertEqual(vr.missing_deployments(list(vr.REQUIRED_DEPLOYMENTS) + ["runai-scheduler-default"],
                                                scheduler_name="runai-scheduler"), [])
        self.assertEqual(vr.missing_deployments(list(vr.REQUIRED_DEPLOYMENTS) + ["kai-scheduler-default"],
                                                scheduler_name="runai-scheduler"), ["runai-scheduler-<shard>"])

    def test_cluster_connected_reads_state_or_platform_or_string(self):
        for status in ({"platform": "Connected"}, {"state": "Connected"}, "Connected"):
            self.assertEqual(vr.cluster_connected({"clusters": [{"name": "d", "status": status}]}, "d"), (True, True))
        self.assertEqual(vr.cluster_connected({"clusters": [{"name": "d", "status": {"state": "Disconnected"}}]}, "d"),
                         (True, False))

    def test_status_summary_only_fixed_words(self):
        # alphabetic secrets, secret-looking key names and nested text must not survive
        doc = {"clusters": [{"name": "d", "status": {
            "state": "Waiting to connect", "platform": "hunter", "status": "SecretTokenAbcdefghijk",
            "PasswordIsHunterTwo": "okvalue", "conditions": [{"message": "token abc"}]}}]}
        out = vr.cluster_status_summary(doc, "d")
        self.assertEqual(out["state"], "Waiting to connect")
        self.assertEqual(out["platform"], "other_text_short")
        self.assertEqual(out["status"], "other_text_long")
        self.assertEqual(out["other_keys"], 2)
        blob = json.dumps(out)
        for bad in ("hunter", "SecretToken", "Password", "okvalue", "token", "abc"):
            self.assertNotIn(bad, blob)
        self.assertEqual(set(out), {"state", "platform", "status", "other_keys"})

    def test_status_summary_string_status(self):
        out = vr.cluster_status_summary({"clusters": [{"name": "d", "status": "Connected"}]}, "d")
        self.assertEqual(out, {"status": "Connected", "other_keys": 0})
        out = vr.cluster_status_summary({"clusters": [{"name": "d", "status": "my-private-note"}]}, "d")
        self.assertEqual(out, {"status": "other_text_long", "other_keys": 0})

    def test_status_summary_types_and_case(self):
        doc = {"clusters": [{"name": "d", "status": {"platform": 7, "state": "connected",
                                                     "status": True, "connected": None}}]}
        out = vr.cluster_status_summary(doc, "d")
        self.assertEqual(out, {"platform": "type_int", "state": "Connected", "status": "bool_true",
                               "connected": "null", "other_keys": 0})
        self.assertEqual(vr.cluster_connected(doc, "d"), (True, True))

    def test_status_summary_one_nested_level_fixed_keys_only(self):
        doc = {"clusters": [{"name": "d", "status": {
            "platform": {"state": "Connected", "message": "token=abc and more", "secret": "hunter2"},
            "state": {"state": {"deep": "x"}}}}]}
        out = vr.cluster_status_summary(doc, "d")
        self.assertEqual(out["platform"], {"state": "Connected", "n_keys": 3})
        self.assertEqual(out["state"], {"state": "type_dict", "n_keys": 1})
        blob = json.dumps(out)
        for bad in ("token", "abc", "hunter", "secret", "message", "deep"):
            self.assertNotIn(bad, blob)
        self.assertEqual(vr.cluster_connected(doc, "d"), (True, True))

    def test_unknown_text_same_bucket_gives_identical_output(self):
        def summ(txt, nested=False):
            st = {"state": txt, "platform": {"state": txt}}
            return json.dumps(vr.cluster_status_summary({"clusters": [{"name": "d", "status": st}]}, "d"),
                              sort_keys=True)
        # different secrets of the same length class must be indistinguishable in the report
        self.assertEqual(summ("hunter2abcdefghijk"), summ("zzzzzzzzzzzzzzzzzz"))
        self.assertEqual(summ("tok"), summ("pwd"))
        self.assertNotEqual(summ("tok"), summ("a-much-longer-unknown-value"))
        for bad in ("hunter", "zzzz", "sha", "len"):
            self.assertNotIn(bad, summ("hunter2abcdefghijk"))

    def test_separators_and_case_ignored_in_fixed_words(self):
        doc = {"clusters": [{"name": "d", "status": {"state": "WaitingToConnect", "platform": "waiting_for-data"}}]}
        out = vr.cluster_status_summary(doc, "d")
        self.assertEqual(out["state"], "Waiting to connect")
        self.assertEqual(out["platform"], "Waiting for data")


class TestArgs(unittest.TestCase):
    def test_bad_namespace_refused(self):
        with self.assertRaises(SystemExit):
            args("--namespace", "Bad_Name")

    def test_short_timeout_refused(self):
        with self.assertRaises(SystemExit):
            args("--job-timeout", "1")


if __name__ == "__main__":
    unittest.main()
