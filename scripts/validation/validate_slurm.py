#!/usr/bin/env python3
"""Validate a DeepOps Slurm deployment and report a machine-readable verdict.

Run this on a Slurm controller, login, or compute node after deploying
``playbooks/slurm-cluster.yml``. It checks controller reachability, node
health, GPU (GRES) configuration, and optionally runs a single-GPU job.

The default output is one human-readable line per check. With ``--json`` the
script prints a single flat JSON object with stable field names so automation
and AI agents can consume the result directly.

Exit codes: 0 = all checks passed, 1 = one or more checks failed,
2 = usage or environment error (Slurm commands not found).

Note: on DeepOps Slurm clusters, ``nvidia-smi`` in an ordinary SSH session on
a login/compute node may report "No devices were found" because GPUs are
hidden outside Slurm-managed jobs. That is expected; the authoritative GPU
check is the ``srun`` job this script runs.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys


def run(cmd, timeout=60):
    """Run a command, returning (rc, stdout, stderr) without raising."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except FileNotFoundError:
        return 127, "", "command not found: %s" % cmd[0]


def parse_sinfo_states(output):
    """Parse ``sinfo -h -N -o '%n %T'`` output into node-state counts.

    Returns (nodes_total, nodes_available, nodes_unavailable, states) where
    states maps state name (lowercase, trailing '*' stripped) to a count.
    """
    states = {}
    seen = set()
    for line in output.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        node, state = parts
        if node in seen:
            continue
        seen.add(node)
        state = state.strip().rstrip("*+~#!%$@^-").lower()
        states[state] = states.get(state, 0) + 1
    available_states = ("idle", "mixed", "allocated", "completing")
    available = sum(states.get(s, 0) for s in available_states)
    total = len(seen)
    return total, available, total - available, states


def parse_gres_gpus(output):
    """Parse ``sinfo -h -N -o '%n %G'`` output into a total GPU count."""
    total = 0
    seen = set()
    for line in output.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2 or parts[0] in seen:
            continue
        seen.add(parts[0])
        for match in re.finditer(r"gpu(?::[^:,(\s]+)?:(\d+)", parts[1]):
            total += int(match.group(1))
    return total


def main():
    parser = argparse.ArgumentParser(
        description="Validate a DeepOps Slurm deployment."
    )
    parser.add_argument("--json", action="store_true", help="emit one JSON object")
    parser.add_argument(
        "--skip-gpu-job",
        action="store_true",
        help="skip the srun single-GPU test job",
    )
    parser.add_argument(
        "--allow-unavailable-nodes",
        action="store_true",
        help="do not fail when some nodes are down, drained, or unknown",
    )
    parser.add_argument(
        "--partition",
        default="",
        help="partition for the GPU test job (default: cluster default)",
    )
    parser.add_argument(
        "--gpu-job-timeout",
        type=int,
        default=300,
        help="seconds to wait for the GPU test job (default: 300)",
    )
    args = parser.parse_args()

    if not shutil.which("sinfo"):
        print("error: sinfo not found; run this on a Slurm node", file=sys.stderr)
        return 2

    result = {
        "ok": False,
        "slurm_version": "",
        "controller_reachable": False,
        "nodes_total": 0,
        "nodes_available": 0,
        "nodes_unavailable": 0,
        "node_states": {},
        "gpus_configured": 0,
        "gpu_job_ran": False,
        "gpu_job_ok": False,
        "gpus_visible_in_job": 0,
        "failures": [],
    }

    rc, out, _ = run(["sinfo", "--version"])
    if rc == 0 and out:
        result["slurm_version"] = out.split()[-1]

    rc, out, err = run(["sinfo", "-h", "-N", "-o", "%n %T"])
    if rc != 0:
        result["failures"].append("sinfo failed: %s" % (err or "rc=%s" % rc))
    else:
        result["controller_reachable"] = True
        total, avail, unavail, states = parse_sinfo_states(out)
        result["nodes_total"] = total
        result["nodes_available"] = avail
        result["nodes_unavailable"] = unavail
        result["node_states"] = states
        if total == 0:
            result["failures"].append("no nodes are defined in Slurm")
        if unavail and not args.allow_unavailable_nodes:
            result["failures"].append(
                "%d node(s) unavailable: %s"
                % (unavail, ", ".join(sorted(k for k in states if k not in ("idle", "mixed", "allocated", "completing"))))
            )

    rc, out, _ = run(["sinfo", "-h", "-N", "-o", "%n %G"])
    if rc == 0:
        result["gpus_configured"] = parse_gres_gpus(out)
    if result["controller_reachable"] and result["gpus_configured"] == 0:
        result["failures"].append("no GPUs (gres/gpu) configured on any node")

    if not args.skip_gpu_job and result["controller_reachable"] and result["gpus_configured"] > 0:
        result["gpu_job_ran"] = True
        cmd = ["srun", "--gpus=1", "--time=5"]
        if args.partition:
            cmd += ["--partition", args.partition]
        cmd += ["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]
        rc, out, err = run(cmd, timeout=args.gpu_job_timeout)
        if rc == 0 and out:
            result["gpu_job_ok"] = True
            result["gpus_visible_in_job"] = len(out.splitlines())
        else:
            result["failures"].append(
                "srun GPU job failed: %s" % (err or out or "rc=%s" % rc)
            )

    result["ok"] = not result["failures"]

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for key in (
            "slurm_version",
            "controller_reachable",
            "nodes_total",
            "nodes_available",
            "nodes_unavailable",
            "gpus_configured",
            "gpu_job_ran",
            "gpu_job_ok",
        ):
            print("%s=%s" % (key, result[key]))
        for failure in result["failures"]:
            print("FAIL: %s" % failure)
        print("ok=%s" % result["ok"])
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
