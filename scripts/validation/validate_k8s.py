#!/usr/bin/env python3
"""Validate a DeepOps Kubernetes GPU deployment with a machine-readable verdict.

Run this anywhere ``kubectl`` can reach the cluster after deploying
``playbooks/k8s-cluster.yml``. It checks node readiness, allocatable
``nvidia.com/gpu`` resources, GPU stack pod health, and can optionally run a
CUDA smoke pod that requests one GPU.

The default output is one human-readable line per check. With ``--json`` the
script prints a single flat JSON object with stable field names so automation
and AI agents can consume the result directly.

Exit codes: 0 = all checks passed, 1 = one or more checks failed,
2 = usage or environment error (kubectl not found).
"""

import argparse
import json
import shutil
import subprocess
import sys
import time

SMOKE_NAMESPACE = "deepops-validate"
SMOKE_POD = "deepops-validate-cuda"


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


def summarize_nodes(nodes_json):
    """Summarize a ``kubectl get nodes -o json`` document.

    Returns (nodes_total, nodes_ready, gpus_allocatable).
    """
    total = ready = gpus = 0
    for item in nodes_json.get("items", []):
        total += 1
        for cond in item.get("status", {}).get("conditions", []):
            if cond.get("type") == "Ready" and cond.get("status") == "True":
                ready += 1
                break
        alloc = item.get("status", {}).get("allocatable", {})
        try:
            gpus += int(alloc.get("nvidia.com/gpu", "0"))
        except ValueError:
            pass
    return total, ready, gpus


def summarize_gpu_pods(pods_json):
    """Summarize GPU stack pods. Returns (pods_total, pods_ready)."""
    total = ready = 0
    for item in pods_json.get("items", []):
        total += 1
        phase = item.get("status", {}).get("phase", "")
        if phase == "Succeeded":
            ready += 1
            continue
        if phase != "Running":
            continue
        statuses = item.get("status", {}).get("containerStatuses", [])
        if statuses and all(s.get("ready") for s in statuses):
            ready += 1
    return total, ready


def smoke_pod_manifest(image):
    return {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": SMOKE_POD, "namespace": SMOKE_NAMESPACE},
        "spec": {
            "restartPolicy": "Never",
            "containers": [
                {
                    "name": "cuda-smoke",
                    "image": image,
                    "command": ["nvidia-smi", "-L"],
                    "resources": {"limits": {"nvidia.com/gpu": 1}},
                }
            ],
        },
    }


def run_cuda_smoke(result, image, timeout):
    result["cuda_smoke_ran"] = True
    run(["kubectl", "delete", "namespace", SMOKE_NAMESPACE, "--ignore-not-found"], timeout=120)
    rc, _, err = run(["kubectl", "create", "namespace", SMOKE_NAMESPACE])
    if rc != 0:
        result["failures"].append("could not create smoke namespace: %s" % err)
        return
    rc, _, err = run(
        ["kubectl", "apply", "-f", "-"],
        input_text=json.dumps(smoke_pod_manifest(image)),
    )
    if rc != 0:
        result["failures"].append("could not create smoke pod: %s" % err)
        return
    deadline = time.time() + timeout
    phase = ""
    while time.time() < deadline:
        rc, phase, _ = run(
            ["kubectl", "-n", SMOKE_NAMESPACE, "get", "pod", SMOKE_POD,
             "-o", "jsonpath={.status.phase}"]
        )
        if phase in ("Succeeded", "Failed"):
            break
        time.sleep(5)
    rc, logs, _ = run(["kubectl", "-n", SMOKE_NAMESPACE, "logs", SMOKE_POD])
    if phase == "Succeeded" and rc == 0 and "GPU" in logs:
        result["cuda_smoke_ok"] = True
        result["cuda_smoke_gpus"] = sum(
            1 for line in logs.splitlines() if line.startswith("GPU ")
        )
        run(["kubectl", "delete", "namespace", SMOKE_NAMESPACE, "--ignore-not-found"], timeout=120)
    else:
        result["failures"].append(
            "CUDA smoke pod did not succeed (phase=%s); namespace %s kept for debugging"
            % (phase or "unknown", SMOKE_NAMESPACE)
        )


def main():
    parser = argparse.ArgumentParser(
        description="Validate a DeepOps Kubernetes GPU deployment."
    )
    parser.add_argument("--json", action="store_true", help="emit one JSON object")
    parser.add_argument(
        "--cuda-smoke",
        action="store_true",
        help="run a CUDA pod requesting one GPU (creates and deletes namespace %s)"
        % SMOKE_NAMESPACE,
    )
    parser.add_argument(
        "--cuda-image",
        default="nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04",
        help="image for the CUDA smoke pod",
    )
    parser.add_argument(
        "--smoke-timeout",
        type=int,
        default=600,
        help="seconds to wait for the CUDA smoke pod (default: 600)",
    )
    parser.add_argument(
        "--allow-no-gpus",
        action="store_true",
        help="do not fail when the cluster has no allocatable GPUs",
    )
    args = parser.parse_args()

    if not shutil.which("kubectl"):
        print("error: kubectl not found in PATH", file=sys.stderr)
        return 2

    result = {
        "ok": False,
        "api_reachable": False,
        "nodes_total": 0,
        "nodes_ready": 0,
        "gpus_allocatable": 0,
        "gpu_stack_pods_total": 0,
        "gpu_stack_pods_ready": 0,
        "cuda_smoke_ran": False,
        "cuda_smoke_ok": False,
        "cuda_smoke_gpus": 0,
        "failures": [],
    }

    rc, out, err = run(["kubectl", "get", "nodes", "-o", "json"], timeout=120)
    if rc != 0:
        result["failures"].append("kubectl get nodes failed: %s" % (err or "rc=%s" % rc))
    else:
        result["api_reachable"] = True
        try:
            total, ready, gpus = summarize_nodes(json.loads(out))
        except json.JSONDecodeError:
            result["failures"].append("could not parse kubectl node output")
            total = ready = gpus = 0
        result["nodes_total"] = total
        result["nodes_ready"] = ready
        result["gpus_allocatable"] = gpus
        if total == 0:
            result["failures"].append("cluster reports zero nodes")
        elif ready < total:
            result["failures"].append(
                "%d of %d nodes are not Ready" % (total - ready, total)
            )
        if gpus == 0 and not args.allow_no_gpus:
            result["failures"].append(
                "no allocatable nvidia.com/gpu resources; check GPU Operator or device plugin"
            )

    if result["api_reachable"]:
        rc, out, _ = run(
            ["kubectl", "get", "pods", "--all-namespaces",
             "-l", "app.kubernetes.io/managed-by in (gpu-operator)", "-o", "json"],
            timeout=120,
        )
        pods_total = pods_ready = 0
        if rc == 0:
            try:
                pods_total, pods_ready = summarize_gpu_pods(json.loads(out))
            except json.JSONDecodeError:
                pass
        result["gpu_stack_pods_total"] = pods_total
        result["gpu_stack_pods_ready"] = pods_ready
        if pods_total and pods_ready < pods_total:
            result["failures"].append(
                "%d of %d GPU stack pods are not ready" % (pods_total - pods_ready, pods_total)
            )

    if args.cuda_smoke and result["api_reachable"] and result["gpus_allocatable"] > 0:
        run_cuda_smoke(result, args.cuda_image, args.smoke_timeout)

    result["ok"] = not result["failures"]

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for key in (
            "api_reachable",
            "nodes_total",
            "nodes_ready",
            "gpus_allocatable",
            "gpu_stack_pods_total",
            "gpu_stack_pods_ready",
            "cuda_smoke_ran",
            "cuda_smoke_ok",
            "cuda_smoke_gpus",
        ):
            print("%s=%s" % (key, result[key]))
        for failure in result["failures"]:
            print("FAIL: %s" % failure)
        print("ok=%s" % result["ok"])
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
