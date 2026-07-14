---
name: deploy-slurm-cluster
description: Deploy a Slurm GPU cluster with DeepOps and prove it works. Use when asked to deploy, install, or rebuild Slurm on one or more GPU servers with this repository.
---

# Deploy a Slurm GPU cluster

## Preconditions

- Ubuntu 22.04/24.04 or RHEL/Rocky 8/9 hosts you may fully manage (driver
  installs may reboot them; no active users or workloads).
- SSH access from the provisioning machine to every host as a sudo-capable
  user.
- Run everything from the repository root.

## Procedure

1. Prepare the environment and verify it:

   ```bash
   git submodule update --init --recursive
   ./scripts/setup.sh
   cp -r config.example config
   ```

2. Edit `config/inventory`: put the controller under `[slurm-master]` and
   compute nodes under `[slurm-node]` (a single machine can be both). Set
   the connection user in `[all:vars]` if not root.

3. Preflight — must pass before deploying:

   ```bash
   python3 scripts/validation/deepops_doctor.py --remote --json
   ```

   Fix anything in `failures` (each check's `detail` says how) and rerun.

4. Deploy:

   ```bash
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
   ```

   This installs NVIDIA drivers, builds and configures Slurm, and sets up
   munge, NFS, and node health checks. Expect roughly 30–60 minutes on a
   first run.

5. Validate on a cluster node — the success signal is this, not the play
   recap:

   ```bash
   python3 scripts/validation/validate_slurm.py --json
   ```

   Require `"ok": true` with `gpu_job_ok: true` and
   `nodes_unavailable: 0`.

## Failure branches

- **Playbook fails on a transient error** (mirror timeout, apt lock,
  network blip): rerun the same playbook; it is idempotent. A converged
  rerun ends with `changed=0`.
- **`nvidia-smi` works in the validator's srun job but "fails" over SSH**:
  that is the login GPU-hide behavior, not an error (see AGENTS.md
  gotchas).
- **`gpu_job_ok: false` with driver errors**: follow
  `skills/diagnose-driver-install/`.
- **Node shows `down` or `drained` in `node_states`**: check
  `scontrol show node <name>` for the reason; after fixing, resume with
  `scontrol update nodename=<name> state=resume`.
- **Wrong or stale host facts after reprovisioning a node**: rerun with
  `--flush-cache`.
