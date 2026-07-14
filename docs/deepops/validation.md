# Validating a DeepOps deployment

DeepOps ships small validation tools that answer one question with a stable,
machine-readable contract: **did the deployment work?** They are safe to run
repeatedly, designed for both humans and automation (including AI agents),
and complement the heavier workload tests under `workloads/`.

All three tools:

- print one human-readable line per check by default, or a single flat JSON
  object with `--json`
- exit `0` when every check passes, `1` when any check fails, and `2` on
  usage or environment errors
- fail loudly with a `failures` list explaining exactly what is wrong

## Preflight: `scripts/validation/deepops_doctor.py`

Run from the DeepOps repository root on the provisioning machine before
running cluster playbooks:

```bash
python3 scripts/validation/deepops_doctor.py
python3 scripts/validation/deepops_doctor.py --remote   # adds SSH checks
python3 scripts/validation/deepops_doctor.py --json
```

Local checks: Ansible present, Galaxy dependencies installed, the Kubespray
submodule initialized, the configuration directory present, and the inventory
parseable with at least one host. With `--remote` it also verifies host
reachability (`ansible -m ping`), reports which hosts have NVIDIA PCI
devices, and reports sshd systemd overrides (see the GPU visibility note
below).

## Slurm: `scripts/validation/validate_slurm.py`

Run on any Slurm cluster node after `playbooks/slurm-cluster.yml`:

```bash
python3 scripts/validation/validate_slurm.py
python3 scripts/validation/validate_slurm.py --json
python3 scripts/validation/validate_slurm.py --skip-gpu-job   # read-only
```

Checks controller reachability, node availability, configured `gres/gpu`
resources, and (by default) submits a single-GPU `srun` job running
`nvidia-smi`. Example JSON:

```json
{
  "ok": true,
  "slurm_version": "26.05.1",
  "controller_reachable": true,
  "nodes_total": 1,
  "nodes_available": 1,
  "nodes_unavailable": 0,
  "node_states": {"idle": 1},
  "gpus_configured": 1,
  "gpu_job_ran": true,
  "gpu_job_ok": true,
  "gpus_visible_in_job": 1,
  "failures": []
}
```

### GPU visibility note

On DeepOps Slurm clusters, GPUs are hidden from ordinary SSH sessions on
cluster nodes; `nvidia-smi` outside a Slurm job may report
`No devices were found` even when the GPUs and driver are healthy. This is
expected behavior, not a failure. The authoritative check is the `srun` job
this script runs.

## Kubernetes: `scripts/validation/validate_k8s.py`

Run anywhere `kubectl` reaches the cluster after `playbooks/k8s-cluster.yml`:

```bash
python3 scripts/validation/validate_k8s.py
python3 scripts/validation/validate_k8s.py --cuda-smoke
python3 scripts/validation/validate_k8s.py --json --cuda-smoke
```

Checks API reachability, node readiness, allocatable `nvidia.com/gpu`
resources, and GPU Operator pod health. With `--cuda-smoke` it creates a
temporary `deepops-validate` namespace, runs a CUDA pod that requests one GPU
and lists it with `nvidia-smi -L`, and deletes the namespace on success (the
namespace is kept on failure for debugging).

For an exhaustive every-GPU job test, see `scripts/k8s/verify_gpu.sh`.

## Testing the tools

```bash
python3 -m unittest discover -s scripts/validation/tests
```
