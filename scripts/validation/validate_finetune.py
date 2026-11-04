#!/usr/bin/env python3
"""Read-only single-node fine-tuning readiness; never train or download by default.

Run as the model consumer on the selected Slurm compute host. Optional
--gpu-smoke submits one bounded Pyxis container job and may pull its image.
Exit codes: 0 ready, 1 not ready, 2 bad input. Training is never validated.
"""
import argparse
import json
import math
from pathlib import Path, PurePosixPath
import re
import socket
import subprocess
import sys

from validate_model_cache import validate as validate_cache


class BadInput(ValueError):
    """Invalid request, reported without raw arguments."""


def run(command, timeout):
    """Bound local probes; never invoke a shell or expose command output on failure."""
    try:
        process = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return process.returncode, process.stdout.strip(), ""
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        return 1, "", "command unavailable or timed out"


def new_result():
    return {
        "schema_version": 1, "status": "not_ready", "ok": False,
        "training_validated": False, "gpu_smoke_ran": False, "gpu_smoke_ok": False,
        "checks": {name: False for name in ("scheduler", "local_node", "gpu_capacity", "container_support", "cache", "container_pin")},
        "errors": [],
    }


def safe_relative(value):
    return (isinstance(value, str) and bool(value) and value != "."
            and not PurePosixPath(value).is_absolute() and ".." not in PurePosixPath(value).parts
            and str(PurePosixPath(value)) == value and "\\" not in value)


def check_arguments(args):
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 120:
        raise BadInput("timeout must be greater than zero and at most 120 seconds")
    for name in ("node", "partition"):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", getattr(args, name)):
            raise BadInput("node and partition must each name one explicit target, not a range or list")
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        raise BadInput("revision must be a full lowercase 40-character commit hash")
    parts = args.repo_id.split("/")
    if (len(parts) not in (1, 2) or len(args.repo_id) > 96 or any(
            not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", part)
            or part.endswith((".", "-")) or ".." in part or "--" in part for part in parts)):
        raise BadInput("repo-id must be a model name or namespace/model")
    if not args.require_file or not all(safe_relative(name) for name in args.require_file):
        raise BadInput("require-file must contain normalized relative model paths without traversal")
    # Pyxis/Enroot registry#repository syntax. Digest-only: mutable tags are not pins.
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*(?::[0-9]{1,5})?#[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}", args.container_image):
        raise BadInput("container-image must use registry#repository@sha256:<64 lowercase hex digits>, without credentials")


def parse_record(output):
    """Require one unambiguous scontrol --oneliner record."""
    if len(output.splitlines()) != 1:
        return {}
    record = {}
    for item in output.split():
        if "=" in item:
            key, value = item.split("=", 1)
            if key in record:
                return {}
            record[key] = value
    return record


def gpu_count(tres):
    matches = re.findall(r"(?:^|,)gres/gpu=(\d+)(?:,|$)", tres)
    return int(matches[0]) if len(matches) == 1 else None


def cache_ready(args):
    """Verify explicit files plus all shards of the supported safetensors layout.

    This checks completeness of this layout, not model semantics or integrity.
    Other tokenizers/weight formats require a separately reviewed recipe.
    """
    required = set(args.require_file)
    if not {"config.json", "tokenizer.json", "tokenizer_config.json"}.issubset(required):
        return False
    index_name = "model.safetensors.index.json"
    if not ({"model.safetensors", index_name} & required):
        return False
    result = validate_cache(args.cache_dir, args.repo_id, args.revision, args.require_file)
    if not result["ok"]:
        return False
    if index_name in required:
        try:
            index_path = Path(result["snapshot_path"]) / index_name
            if index_path.stat().st_size > 8 * 1024 * 1024:
                return False
            with index_path.open("rb") as stream:
                raw = stream.read(8 * 1024 * 1024 + 1)
            if len(raw) > 8 * 1024 * 1024:
                return False
            index = json.loads(raw)
            weights = index.get("weight_map") if isinstance(index, dict) else None
            if (not isinstance(weights, dict) or not weights
                    or not all(safe_relative(name) and name.endswith(".safetensors") for name in weights.values())):
                return False
            return validate_cache(args.cache_dir, args.repo_id, args.revision, sorted(required | set(weights.values())))["ok"]
        except (OSError, ValueError, UnicodeError, RecursionError):
            return False
    return True


def validate(args):
    result = new_result()

    def check(stage, passed, message):
        result["checks"][stage] = bool(passed)
        if not passed:
            result["errors"].append({"stage": stage, "message": message})

    try:
        check_arguments(args)
    except BadInput as exc:
        result["status"] = "bad_input"
        result["errors"].append({"stage": "arguments", "message": str(exc)})
        return result
    result["checks"]["container_pin"] = True
    rc, output, _ = run(["scontrol", "show", "node", "--oneliner", args.node], args.timeout)
    node = parse_record(output) if rc == 0 else {}
    rc, output, _ = run(["scontrol", "show", "partition", "--oneliner", args.partition], args.timeout)
    partition = parse_record(output) if rc == 0 else {}
    check("scheduler", node.get("NodeName") == args.node and bool(node.get("State"))
          and partition.get("PartitionName") == args.partition and partition.get("State") == "UP"
          and args.partition in node.get("Partitions", "").split(","),
          "scheduler must return the selected node in the selected UP partition")
    local_names = {socket.gethostname(), socket.gethostname().split(".")[0]}
    check("local_node", node.get("NodeHostName") in local_names,
          "run as the consumer on the selected compute host; remote runtime and cache are not verified")
    configured = gpu_count(node.get("CfgTRES", ""))
    # Slurm emits an empty AllocTRES when nothing is allocated.
    allocated = gpu_count(node.get("AllocTRES", ""))
    if allocated is None and "AllocTRES" in node and not node["AllocTRES"]:
        allocated = 0
    check("gpu_capacity", node.get("State") == "IDLE" and configured is not None and configured >= 1
          and allocated == 0,
          "selected node must be IDLE with at least one configured GPU and no allocated GPUs; mixed or flagged nodes are not accepted")
    runtime_rc, runtime, _ = run(["enroot", "version"], args.timeout)
    plugin_rc, help_text, _ = run(["srun", "--help"], args.timeout)
    check("container_support", runtime_rc == 0 and bool(runtime) and plugin_rc == 0
          and "--container-image" in help_text and "--container-mounts" in help_text,
          "local Enroot and Slurm Pyxis container options must be available; execution requires the optional probe")
    check("cache", cache_ready(args),
          "cache must contain readable nonempty config, tokenizer, and safetensors weights, including all indexed shards and explicitly required files")
    if args.gpu_smoke and not result["errors"]:
        result["gpu_smoke_ran"] = True
        command = ["srun", "--nodes=1", "--ntasks=1", "--gpus=1", "--immediate=5", "--time=1",
                   "--nodelist=" + args.node, "--partition=" + args.partition,
                   "--container-image=" + args.container_image,
                   "nvidia-smi", "--query-gpu=index,name", "--format=csv,noheader"]
        rc, output, _ = run(command, args.timeout)
        result["gpu_smoke_ok"] = rc == 0 and bool(re.fullmatch(r"\d+,\s*[^\n,]+", output))
        if not result["gpu_smoke_ok"]:
            result["errors"].append({"stage": "gpu_smoke", "message": "optional container job failed or did not report exactly one GPU"})
    result["ok"] = not result["errors"]
    result["status"] = "ready" if result["ok"] else "not_ready"
    return result


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise BadInput("missing, invalid, or unsupported arguments; use --help")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = Parser(description=__doc__, allow_abbrev=False)
    for name in ("cache-dir", "repo-id", "revision", "node", "partition", "container-image"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--require-file", required=True, action="append")
    parser.add_argument("--timeout", type=float, default=30, help="Per-command bound, 0 < seconds <= 120")
    parser.add_argument("--gpu-smoke", action="store_true", help="Opt in to one GPU container job; may pull the image, never trains")
    parser.add_argument("--json", action="store_true")
    try:
        args = parser.parse_args(argv)
        result = validate(args)
    except BadInput as exc:
        result = new_result()
        result["status"] = "bad_input"
        result["errors"].append({"stage": "arguments", "message": str(exc)})
    if "--json" in argv:
        print(json.dumps(result, sort_keys=True))
    else:
        print(result["status"] + ": readiness only; training_validated=false")
        for error in result["errors"]:
            print(error["stage"] + ": " + error["message"])
    return {"ready": 0, "not_ready": 1, "bad_input": 2}[result["status"]]


if __name__ == "__main__":
    sys.exit(main())
