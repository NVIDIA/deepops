#!/usr/bin/env python3
"""Validate an optional KAI Scheduler / Run:ai install on a DeepOps Kubernetes cluster.

Run anywhere ``kubectl`` reaches the cluster after ``playbooks/k8s-cluster/runai.yml``.
The verdict is strict JSON with ``--json``: ``"ok": true`` only if every check that
applies to the selected mode passed.

Checks (all in a fresh namespace this run creates (it refuses an existing one) and deletes on success):

1. scheduler pods are available and the KAI queue API exists
2. a whole-GPU pod scheduled by KAI runs ``nvidia-smi -L`` and completes
3. two pods asking for half a GPU each land on the same GPU and complete
4. ``--memory-enforcement``: a pod inside its GPU-memory share completes and a pod
   that allocates past it is refused (gpu-fractioning only)
5. ``--mode platform``: the control-plane API answers over the configured domain
   and the cluster reports ``Connected``

``--verify-uninstalled`` is a separate read-only mode: it passes only if no
``kai-scheduler``/``runai*`` namespace or Helm release is left.

Exit codes: 0 = ok, 1 = not ok, 2 = bad input or kubectl missing.
"""

import argparse
import http.client
import json
import re
import shutil
import ssl
import subprocess
import sys
import time
import urllib.parse

SCHEMA_VERSION = 1
OWNER_LABEL = "deepops.nvidia.com/runai-validate"
OWNER_VALUE = "owned"
KAI_NAMESPACE = "kai-scheduler"
# The operator names the scheduler Deployment "<schedulerName>-<shard>" (kai-scheduler-default).
REQUIRED_DEPLOYMENTS = ("kai-operator", "binder", "queue-controller", "admission")
SCHEDULER_PREFIX = "kai-scheduler-"
LEFTOVER_NAMESPACES = re.compile(r"^(kai-scheduler|kai-resource-reservation|runai.*)$")
NAME_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
FQDN_RE = re.compile(r"^[A-Za-z0-9]([-A-Za-z0-9.]*[A-Za-z0-9])?$")

# Allocates past a GPU-memory share using only the CUDA driver library, so a plain
# Python image is enough. Prints a stable marker the validator can match.
ALLOC_SCRIPT = (
    "import ctypes,sys\n"
    "mib=int(sys.argv[1])\n"
    "c=ctypes.CDLL('libcuda.so.1')\n"
    "def chk(r,w):\n"
    "    if r!=0:\n"
    "        print('ALLOC_FAILED %s rc=%d'%(w,r)); sys.exit(7)\n"
    "chk(c.cuInit(0),'init')\n"
    "d=ctypes.c_int(); chk(c.cuDeviceGet(ctypes.byref(d),0),'device')\n"
    "x=ctypes.c_void_p(); chk(c.cuCtxCreate_v2(ctypes.byref(x),0,d),'context')\n"
    "p=ctypes.c_ulonglong(); chk(c.cuMemAlloc_v2(ctypes.byref(p),ctypes.c_size_t(mib<<20)),'alloc')\n"
    "print('ALLOC_OK %d'%mib)\n"
)


def run(cmd, timeout=60, input_text=None):
    """Run a command, returning (rc, stdout, stderr) without raising."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, input=input_text
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except FileNotFoundError:
        return 127, "", "command not found: %s" % cmd[0]


# ---------------------------------------------------------------- pure parsers


def summarize_deployments(deploy_json):
    """Return (names, not_available) for a ``kubectl get deployments -o json`` doc."""
    names, bad = [], []
    for item in deploy_json.get("items", []):
        name = item.get("metadata", {}).get("name", "")
        names.append(name)
        want = item.get("spec", {}).get("replicas", 1)
        have = item.get("status", {}).get("availableReplicas", 0) or 0
        if want and have < want:
            bad.append("%s (%d/%d available)" % (name, have, want))
    return sorted(names), sorted(bad)


def missing_deployments(names, required=REQUIRED_DEPLOYMENTS):
    missing = [r for r in required if r not in names]
    if not any(n.startswith(SCHEDULER_PREFIX) for n in names):
        missing.append(SCHEDULER_PREFIX + "<shard>")
    return missing


def pod_placement(pod_json):
    """Return (node, gpu_group, pod_group) for a pod, or empty strings."""
    meta = pod_json.get("metadata", {})
    return (
        pod_json.get("spec", {}).get("nodeName", "") or "",
        (meta.get("labels") or {}).get("runai-gpu-group", ""),
        (meta.get("annotations") or {}).get("pod-group-name", ""),
    )


def same_gpu(placements):
    """True if every placement has a node and the same non-empty GPU group."""
    if len(placements) < 2:
        return False
    nodes = {p[0] for p in placements}
    groups = {p[1] for p in placements}
    return len(nodes) == 1 and "" not in nodes and len(groups) == 1 and "" not in groups


def leftovers(namespaces_json, releases_json):
    """Names of namespaces/Helm releases that an uninstall should have removed."""
    found = []
    for item in namespaces_json.get("items", []):
        name = item.get("metadata", {}).get("name", "")
        if LEFTOVER_NAMESPACES.match(name):
            found.append("namespace/" + name)
    for rel in releases_json or []:
        chart = rel.get("chart", "")
        if re.match(r"^(kai-scheduler|gpu-fractioning|runai-cluster|control-plane)-", chart):
            found.append("release/%s/%s" % (rel.get("namespace", ""), rel.get("name", "")))
    return sorted(found)


def cluster_connected(clusters_json, cluster_name):
    """Return (found, connected) for a ``GET /api/v1/clusters`` document."""
    items = clusters_json if isinstance(clusters_json, list) else clusters_json.get("clusters", [])
    for item in items:
        if item.get("name") == cluster_name:
            status = item.get("status") or {}
            return True, status.get("platform") == "Connected"
    return False, False


def pod_manifest(name, namespace, image, command, args, scheduler, queue_label, queue,
                 gpu_limit=0, annotations=None, container="gpu-workload", env=None):
    limits = {"nvidia.com/gpu": gpu_limit} if gpu_limit else {}
    spec = {
        "restartPolicy": "Never",
        "schedulerName": scheduler,
        "automountServiceAccountToken": False,
        "containers": [{"name": container, "image": image, "command": command, "args": args}],
    }
    if limits:
        spec["containers"][0]["resources"] = {"limits": limits}
    if env:
        spec["containers"][0]["env"] = [{"name": k, "value": v} for k, v in sorted(env.items())]
    meta = {"name": name, "namespace": namespace, "labels": {queue_label: queue}}
    if annotations:
        meta["annotations"] = annotations
    return {"apiVersion": "v1", "kind": "Pod", "metadata": meta, "spec": spec}


# ------------------------------------------------------------------ kube access


class Kube:
    """Thin kubectl wrapper; tests replace ``run`` on the module."""

    def get_json(self, args, timeout=60):
        rc, out, err = run(["kubectl"] + args + ["-o", "json"], timeout=timeout)
        if rc != 0:
            return None, err or "rc=%s" % rc
        try:
            return json.loads(out), ""
        except json.JSONDecodeError:
            return None, "unparseable kubectl output"

    def apply(self, manifest):
        return run(["kubectl", "apply", "-f", "-"], input_text=json.dumps(manifest))

    def wait_phase(self, namespace, pod, phases, timeout):
        deadline = time.time() + timeout
        phase = ""
        while time.time() < deadline:
            rc, phase, _ = run(["kubectl", "-n", namespace, "get", "pod", pod,
                                "-o", "jsonpath={.status.phase}"])
            if rc == 0 and phase in phases:
                return phase
            time.sleep(3)
        return phase or "Unknown"

    def logs(self, namespace, pod):
        return run(["kubectl", "-n", namespace, "logs", pod])[1]

    def __init__(self):
        # namespace name -> UID of the namespace this run created (or adopted because it
        # created its owner). delete_namespace() refuses anything not in here and deletes
        # with a server-side UID precondition, never by name alone.
        self.owned = {}
        self.delete_note = ""

    def namespace_exists(self, namespace):
        """True/False, or None if the answer is unknown (treated as 'exists')."""
        rc, out, _ = run(["kubectl", "get", "namespace", namespace, "--ignore-not-found",
                          "-o", "name"])
        if rc != 0:
            return None
        return bool(out)

    def own_namespace(self, namespace, uid):
        """Record a namespace (by UID) that this run is allowed to delete."""
        self.owned[namespace] = uid

    def delete_namespace(self, namespace):
        """Delete a namespace only if this run created it and it still has the recorded UID.

        The UID is enforced by the API server (DeleteOptions.preconditions.uid), so a
        namespace that was deleted and re-created under the same name is left alone (409).
        Returns True if the server accepted the delete.
        """
        uid = self.owned.pop(namespace, "")
        if not uid:
            return False
        status, msg = delete_with_uid("/api/v1/namespaces/" + urllib.parse.quote(namespace), uid)
        if status in (200, 202):
            return True
        if status == 404:
            return False
        self.delete_note = ("namespace %s was NOT deleted (HTTP %s: %s); it is not the one this run "
                            "created or could not be checked; leaving it alone" % (namespace, status, msg))
        return False

    def ensure_namespace(self, namespace):
        """Create a fresh, labelled test namespace and record its UID. Never touches an existing one.

        The create is atomic on the server (AlreadyExists if anyone got there first), and the
        UID comes from the create response itself, so there is no read-then-act gap.
        """
        if self.namespace_exists(namespace) is not False:
            return 1, "", "namespace %s already exists (or could not be checked); not touching it" % namespace
        manifest = {"apiVersion": "v1", "kind": "Namespace",
                    "metadata": {"name": namespace, "labels": {OWNER_LABEL: OWNER_VALUE}}}
        rc, out, err = run(["kubectl", "create", "-f", "-", "-o", "json"],
                           input_text=json.dumps(manifest))
        if rc != 0:
            return rc, out, err
        try:
            doc = json.loads(out)
            uid = doc["metadata"]["uid"]
            if doc["metadata"]["name"] != namespace or not uid:
                raise ValueError
        except (ValueError, KeyError, TypeError):
            return 1, "", "namespace %s created but its UID could not be read; not deleting it" % namespace
        self.owned[namespace] = uid
        return rc, out, err


def delete_with_uid(path, uid, timeout=60):
    """DELETE an API path with a UID precondition via a short-lived ``kubectl proxy``.

    (``kubectl delete --raw`` cannot send a request body, so it cannot carry preconditions.)
    Returns (http_status, message); status 0 means the delete was not attempted or not sent.
    """
    try:
        proxy = subprocess.Popen(["kubectl", "proxy", "--port=0", "--address=127.0.0.1"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except OSError as exc:
        return 0, "kubectl proxy: %s" % type(exc).__name__
    try:
        line = proxy.stdout.readline()
        m = re.search(r"127\.0\.0\.1:(\d+)", line)
        if not m:
            return 0, "kubectl proxy did not start"
        conn = http.client.HTTPConnection("127.0.0.1", int(m.group(1)), timeout=timeout)
        body = json.dumps({"apiVersion": "v1", "kind": "DeleteOptions",
                           "propagationPolicy": "Background", "preconditions": {"uid": uid}})
        conn.request("DELETE", path, body, {"Content-Type": "application/json"})
        resp = conn.getresponse()
        resp.read()
        return resp.status, resp.reason
    except (OSError, http.client.HTTPException) as exc:
        return 0, type(exc).__name__
    finally:
        proxy.terminate()
        try:
            proxy.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proxy.kill()


# ------------------------------------------------------------------- the checks


def check_scheduler(kube, result, args):
    doc, err = kube.get_json(["-n", args.kai_namespace, "get", "deployments"])
    if doc is None:
        result["failures"].append("could not list deployments in %s: %s" % (args.kai_namespace, err))
        return
    names, bad = summarize_deployments(doc)
    missing = missing_deployments(names)
    if missing:
        result["failures"].append("scheduler deployments missing: %s" % ", ".join(missing))
    if bad:
        result["failures"].append("scheduler deployments not available: %s" % ", ".join(bad))
    crd, _ = kube.get_json(["get", "crd", "queues.scheduling.run.ai"])
    if crd is None:
        result["failures"].append("queue CRD queues.scheduling.run.ai not found")
    if not missing and not bad and crd is not None:
        result["scheduler_ready"] = True


def run_pod(kube, result, args, manifest, phases=("Succeeded", "Failed")):
    rc, _, err = kube.apply(manifest)
    if rc != 0:
        result["failures"].append("could not create pod %s: %s" % (manifest["metadata"]["name"], err))
        return ""
    return kube.wait_phase(manifest["metadata"]["namespace"], manifest["metadata"]["name"],
                           phases, args.job_timeout)


def check_whole_gpu(kube, result, args):
    result["gpu_job_ran"] = True
    name = "kai-whole-gpu"
    manifest = pod_manifest(name, args.namespace, args.image, ["nvidia-smi"], ["-L"],
                            args.scheduler_name, args.queue_label_key, args.queue, gpu_limit=1)
    phase = run_pod(kube, result, args, manifest)
    if not phase:
        return
    pod, _ = kube.get_json(["-n", args.namespace, "get", "pod", name])
    node, _, group = pod_placement(pod or {})
    logs = kube.logs(args.namespace, name)
    if phase != "Succeeded" or "GPU " not in logs:
        result["failures"].append("whole-GPU pod did not complete (phase=%s)" % phase)
    elif not group:
        result["failures"].append("whole-GPU pod ran but KAI did not group it (no pod-group-name)")
    else:
        result["gpu_job_ok"] = True
        result["gpu_job_node"] = node


def check_fractions(kube, result, args):
    result["fraction_job_ran"] = True
    names = ["kai-half-a", "kai-half-b"]
    for name in names:
        manifest = pod_manifest(
            name, args.namespace, args.image, ["sh", "-c"], ["nvidia-smi -L && sleep 30"],
            args.scheduler_name, args.queue_label_key, args.queue,
            annotations={"gpu-fraction": "0.5"})
        rc, _, err = kube.apply(manifest)
        if rc != 0:
            result["failures"].append("could not create %s: %s" % (name, err))
            return
    for name in names:
        phase = kube.wait_phase(args.namespace, name, ("Running", "Succeeded", "Failed"),
                                args.job_timeout)
        if phase not in ("Running", "Succeeded"):
            result["failures"].append("fractional pod %s did not start (phase=%s)" % (name, phase))
            return
    placements = []
    for name in names:
        pod, _ = kube.get_json(["-n", args.namespace, "get", "pod", name])
        placements.append(pod_placement(pod or {}))
    if not same_gpu(placements):
        result["failures"].append(
            "half-GPU pods did not share one GPU (placements=%s)" % [list(p[:2]) for p in placements])
        return
    for name in names:
        phase = kube.wait_phase(args.namespace, name, ("Succeeded", "Failed"), args.job_timeout)
        if phase != "Succeeded" or "GPU " not in kube.logs(args.namespace, name):
            result["failures"].append("fractional pod %s did not complete (phase=%s)" % (name, phase))
            return
    result["fraction_job_ok"] = True


def memory_pod(name, args, request_mib, limit_mib, alloc_mib):
    ann = {
        "nvidia.com/container.gpu-workload.gpu-memory.request": "%dMi" % request_mib,
        "nvidia.com/container.gpu-workload.gpu-memory.limit": "%dMi" % limit_mib,
    }
    return pod_manifest(name, args.namespace, args.memory_image, ["python3", "-c"],
                        [ALLOC_SCRIPT, str(alloc_mib)], args.scheduler_name,
                        args.queue_label_key, args.queue, annotations=ann,
                        env={"NVIDIA_DRIVER_CAPABILITIES": "compute,utility"})


def check_memory_enforcement(kube, result, args):
    result["memory_enforcement_ran"] = True
    inside = memory_pod("kai-mem-inside", args, 1024, 1024, 256)
    outside = memory_pod("kai-mem-outside", args, 1024, 1024, 4096)
    phase = run_pod(kube, result, args, inside)
    if phase != "Succeeded" or "ALLOC_OK" not in kube.logs(args.namespace, "kai-mem-inside"):
        result["failures"].append("pod inside its GPU-memory share did not complete (phase=%s)" % phase)
        return
    phase = run_pod(kube, result, args, outside)
    logs = kube.logs(args.namespace, "kai-mem-outside")
    if phase == "Failed" and "ALLOC_FAILED alloc" in logs:
        result["memory_enforcement_ok"] = True
    else:
        result["failures"].append(
            "pod past its GPU-memory share was not refused (phase=%s, alloc_ok=%s)"
            % (phase, "ALLOC_OK" in logs))


class ResolvedHTTPS(http.client.HTTPSConnection):
    """HTTPS to ``ip`` while sending SNI/Host for ``host`` (like curl --resolve)."""

    def __init__(self, host, ip, port, context, timeout):
        super().__init__(host, port, context=context, timeout=timeout)
        self._ip = ip

    def connect(self):
        sock = socket_create(self._ip, self.port, self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)


def socket_create(ip, port, timeout):
    import socket
    return socket.create_connection((ip, port), timeout)


def https_request(domain, ip, ca_file, method, path, body=None, headers=None, timeout=20):
    context = ssl.create_default_context(cafile=ca_file) if ca_file else ssl.create_default_context()
    conn = ResolvedHTTPS(domain, ip or domain, 443, context, timeout)
    try:
        conn.request(method, path, body=body, headers=headers or {})
        resp = conn.getresponse()
        return resp.status, resp.read(1024 * 1024)
    finally:
        conn.close()


def check_platform(result, args, env):
    result["platform_ran"] = True
    user, pw = env.get("RUNAI_USERNAME", ""), env.get("RUNAI_PASSWORD", "")
    try:
        status, _ = https_request(args.platform_domain, args.resolve_ip, args.ca_file, "GET", "/")
        if status >= 500:
            result["failures"].append("control-plane endpoint returned HTTP %d" % status)
            return
        result["platform_api_ok"] = True
    except (OSError, ssl.SSLError, http.client.HTTPException) as exc:
        result["failures"].append("control-plane endpoint unreachable: %s" % type(exc).__name__)
        return
    if not user or not pw:
        result["failures"].append(
            "RUNAI_USERNAME and RUNAI_PASSWORD are required to check cluster status")
        return
    try:
        form = urllib.parse.urlencode(
            {"grant_type": "password", "username": user, "password": pw})
        status, body = https_request(
            args.platform_domain, args.resolve_ip, args.ca_file, "POST", "/api/v2/token", form,
            {"Content-Type": "application/x-www-form-urlencoded"})
        bearer = json.loads(body).get("access_token", "") if status == 200 else ""
        if not bearer:
            result["failures"].append("API login failed (HTTP %d)" % status)
            return
        status, body = https_request(
            args.platform_domain, args.resolve_ip, args.ca_file, "GET", "/api/v1/clusters",
            headers={"Authorization": "Bearer " + bearer})
        found, connected = cluster_connected(json.loads(body), args.cluster_name) if status == 200 else (False, False)
    except (OSError, ssl.SSLError, http.client.HTTPException, ValueError) as exc:
        result["failures"].append("cluster status request failed: %s" % type(exc).__name__)
        return
    if not found:
        result["failures"].append("cluster %s is not registered" % args.cluster_name)
    elif not connected:
        result["failures"].append("cluster %s is registered but not Connected" % args.cluster_name)
    else:
        result["platform_cluster_connected"] = True


def new_result(mode):
    return {
        "schema_version": SCHEMA_VERSION, "ok": False, "mode": mode,
        "api_reachable": False, "scheduler_ready": False,
        "gpu_job_ran": False, "gpu_job_ok": False, "gpu_job_node": "",
        "fraction_job_ran": False, "fraction_job_ok": False,
        "memory_enforcement_ran": False, "memory_enforcement_ok": False,
        "platform_ran": False, "platform_api_ok": False, "platform_cluster_connected": False,
        "uninstalled_ran": False, "uninstalled_ok": False, "leftovers": [],
        "failures": [],
    }


def verify_uninstalled(kube, result):
    result["uninstalled_ran"] = True
    ns, err = kube.get_json(["get", "namespaces"])
    if ns is None:
        result["failures"].append("could not list namespaces: %s" % err)
        return
    rc, out, _ = run(["helm", "list", "--all-namespaces", "-o", "json"], timeout=60)
    releases = []
    if rc == 0 and out:
        try:
            releases = json.loads(out)
        except json.JSONDecodeError:
            result["failures"].append("could not parse helm list output")
            return
    result["leftovers"] = leftovers(ns, releases)
    if result["leftovers"]:
        result["failures"].append("leftover objects: %s" % ", ".join(result["leftovers"]))
    else:
        result["uninstalled_ok"] = True


def validate(args, env, kube=None):
    kube = kube or Kube()
    result = new_result("uninstalled" if args.verify_uninstalled else args.mode)
    nodes, err = kube.get_json(["get", "nodes"], timeout=120)
    if nodes is None:
        result["failures"].append("kubectl get nodes failed: %s" % err)
        return result
    result["api_reachable"] = True
    if args.verify_uninstalled:
        verify_uninstalled(kube, result)
        result["ok"] = result["uninstalled_ok"] and not result["failures"]
        return result
    check_scheduler(kube, result, args)
    if result["scheduler_ready"] and not args.skip_gpu_jobs:
        if kube.ensure_namespace(args.namespace)[0] != 0:
            result["failures"].append(
                "could not create a fresh namespace %s (an existing namespace is never reused or "
                "deleted; pick another --namespace or remove it yourself)" % args.namespace)
        else:
            check_whole_gpu(kube, result, args)
            check_fractions(kube, result, args)
            if args.memory_enforcement:
                check_memory_enforcement(kube, result, args)
    if args.mode == "platform":
        check_platform(result, args, env)
    ran_ok = (result["scheduler_ready"] and
              (args.skip_gpu_jobs or (result["gpu_job_ok"] and result["fraction_job_ok"])) and
              (not args.memory_enforcement or result["memory_enforcement_ok"]) and
              (args.mode != "platform" or
               (result["platform_api_ok"] and result["platform_cluster_connected"])))
    result["ok"] = bool(ran_ok and not result["failures"])
    if result["ok"] and not args.skip_gpu_jobs:
        kube.delete_namespace(args.namespace)  # no-op unless this run created it (UID-checked)
        if kube.delete_note:
            result["failures"].append(kube.delete_note)
            result["ok"] = False
    elif not args.skip_gpu_jobs and result["gpu_job_ran"]:
        result["failures"].append("namespace %s kept for debugging" % args.namespace)
    return result


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0], allow_abbrev=False)
    p.add_argument("--json", action="store_true", help="emit one JSON object")
    p.add_argument("--mode", choices=("kai", "platform"), default="kai")
    p.add_argument("--verify-uninstalled", action="store_true",
                   help="read-only: pass only if no kai-scheduler/runai* namespace or release remains")
    p.add_argument("--kai-namespace", default=KAI_NAMESPACE)
    p.add_argument("--namespace", default="deepops-runai-validate",
                   help="namespace for the test pods; must not exist yet, created and labelled by this run, deleted on success; in platform mode "
                        "use the project namespace, e.g. runai-<project>)")
    p.add_argument("--queue", default="default-queue")
    p.add_argument("--queue-label-key", default="kai.scheduler/queue")
    p.add_argument("--scheduler-name", default="kai-scheduler")
    p.add_argument("--image", default="nvcr.io/nvidia/cuda:13.0.2-base-ubuntu24.04")
    p.add_argument("--memory-image", default="python:3.12-slim",
                   help="image with python3 for the GPU-memory check")
    p.add_argument("--job-timeout", type=int, default=300, help="seconds per pod (default 300)")
    p.add_argument("--skip-gpu-jobs", action="store_true", help="scheduler health only")
    p.add_argument("--memory-enforcement", action="store_true",
                   help="also prove gpu-fractioning refuses allocations past a pod's share")
    p.add_argument("--platform-domain", default="", help="control-plane FQDN (platform mode)")
    p.add_argument("--resolve-ip", default="", help="connect here instead of resolving the domain")
    p.add_argument("--ca-file", default="", help="CA bundle that signed the control-plane certificate")
    p.add_argument("--cluster-name", default="deepops", help="Run:ai cluster name to look up")
    args = p.parse_args(argv)
    for label, value in (("namespace", args.namespace), ("kai-namespace", args.kai_namespace)):
        if not NAME_RE.match(value):
            p.error("--%s must be a valid Kubernetes name" % label)
    if args.mode == "platform" and not args.verify_uninstalled:
        if not args.platform_domain or not FQDN_RE.match(args.platform_domain):
            p.error("--platform-domain is required in platform mode")
    if args.job_timeout < 10:
        p.error("--job-timeout must be at least 10 seconds")
    return args


def main(argv=None):
    import os
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not shutil.which("kubectl"):
        print("error: kubectl not found in PATH", file=sys.stderr)
        return 2
    result = validate(args, os.environ)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for key in sorted(result):
            if key not in ("failures", "leftovers"):
                print("%s=%s" % (key, result[key]))
        for failure in result["failures"]:
            print("FAIL: %s" % failure)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
