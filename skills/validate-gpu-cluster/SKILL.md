---
name: validate-gpu-cluster
description: Check whether a DeepOps-deployed Slurm or Kubernetes GPU cluster is healthy and report a machine-readable verdict. Use for health checks, post-deploy verification, "is the cluster working?" questions, and after any node or driver change.
---

# Validate a GPU cluster

## Which validator

- Slurm cluster → `scripts/validation/validate_slurm.py` (run on a cluster
  node)
- Kubernetes cluster → `scripts/validation/validate_k8s.py` (run wherever
  `kubectl` reaches the cluster)
- Not deployed yet / checking the provisioning environment →
  `scripts/validation/deepops_doctor.py` (run from the repository root)

All tools support `--json` and exit `0` only when every check passes. Full
contract: `docs/deepops/validation.md`.

## Procedure

1. Run the matching validator with `--json`.

   ```bash
   python3 scripts/validation/validate_slurm.py --json
   python3 scripts/validation/validate_k8s.py --json --cuda-smoke
   ```

   Use `--skip-gpu-job` (Slurm) or omit `--cuda-smoke` (Kubernetes) when a
   strictly read-only check is required — for example on a busy production
   cluster where a test job would queue behind real work.

2. Read the verdict from the JSON, not from ad-hoc commands:
   - `ok: true` — report healthy, include the key counts
     (`nodes_total`, `gpus_configured`/`gpus_allocatable`).
   - `ok: false` — report each entry in `failures` verbatim; they name the
     failing subsystem and the next diagnostic step.

3. When a GPU check fails, do not conclude "driver broken" from a bare
   `nvidia-smi` over SSH — on Slurm nodes GPUs are hidden outside jobs.
   Follow `skills/diagnose-driver-install/` instead.

## Interpreting common results

| Signal | Meaning |
|--------|---------|
| Slurm `nodes_unavailable > 0` | Node down/drained — `scontrol show node <name>` for the reason. |
| Slurm `gpus_configured: 0` | GRES not configured — check `config/group_vars/slurm-cluster.yml` GPU settings and rerun the Slurm playbook. |
| K8s `gpus_allocatable: 0` | GPU Operator stack not ready — `kubectl get pods -A \| grep -i nvidia`; first-deploy driver builds can take 10+ minutes. |
| K8s smoke pod `Pending` | No schedulable GPU or image pull failure — `kubectl -n deepops-validate describe pod`. |
| Direct `nvidia-smi` over SSH says "No devices were found" on a Slurm node | Expected GPU-hide behavior, not a failure. |
