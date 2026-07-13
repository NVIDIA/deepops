---
name: deploy-k8s-gpu-cluster
description: Deploy a Kubernetes GPU cluster with DeepOps (Kubespray + GPU Operator) and prove it schedules GPU pods. Use when asked to deploy or rebuild Kubernetes on GPU servers with this repository.
---

# Deploy a Kubernetes GPU cluster

## Preconditions

- Ubuntu 22.04/24.04 or RHEL/Rocky 8/9 hosts you may fully manage (driver
  installs may reboot them; no active users or workloads).
- SSH access from the provisioning machine to every host as a sudo-capable
  user.
- `submodules/kubespray` initialized — Kubernetes playbooks fail on missing
  `kubespray_defaults` role imports without it.
- Run everything from the repository root.

## Procedure

1. Prepare the environment and verify it:

   ```bash
   git submodule update --init --recursive
   ./scripts/setup.sh
   cp -r config.example config
   ```

2. Edit `config/inventory`: control plane nodes under
   `[kube_control_plane]` and `[etcd]`, workers under `[kube_node]` (a
   single machine can hold all three roles).

3. Preflight — must pass before deploying:

   ```bash
   python3 scripts/validation/deepops_doctor.py --remote --json
   ```

4. Deploy:

   ```bash
   ansible-playbook -l k8s_cluster playbooks/k8s-cluster.yml
   ```

   This runs Kubespray and installs the NVIDIA GPU Operator. Expect
   roughly 45–90 minutes on a first run.

5. Validate — the success signal is this, not the play recap:

   ```bash
   python3 scripts/validation/validate_k8s.py --json --cuda-smoke
   ```

   Require `"ok": true` with `nodes_ready == nodes_total`,
   `gpus_allocatable > 0`, and `cuda_smoke_ok: true`.

## Failure branches

- **Playbook fails on a transient error**: rerun the same playbook;
  Kubespray is rerun-safe. A converged rerun reports `changed=0`.
- **Syntax/import error mentioning `kubespray_defaults`**: the submodule is
  not initialized; run `git submodule update --init --recursive`.
- **`gpus_allocatable: 0`**: the GPU Operator stack is not ready. Check
  `kubectl get pods -A | grep -i nvidia` — the driver DaemonSet can take
  10+ minutes on first deploy; if pods are crash-looping, follow
  `skills/diagnose-driver-install/`.
- **CUDA smoke pod stuck `Pending`**: `kubectl -n deepops-validate
  describe pod deepops-validate-cuda` — usually no allocatable GPU
  (see above) or an image pull problem on airgapped networks (use
  `--cuda-image` to point at a mirrored image).
- **Single-node clusters**: control plane taints are handled by the
  playbook for the single-node case; if pods stay Pending on a multi-role
  node, check taints with `kubectl describe node <name> | grep -i taint`.
