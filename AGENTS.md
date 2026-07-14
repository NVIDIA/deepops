# DeepOps agent operating guide

This file is the entry point for AI agents (and new humans) operating this
repository. DeepOps deploys and manages GPU clusters — Slurm or Kubernetes on
NVIDIA GPU servers — using Ansible. Everything here is driven by playbooks
against an inventory you control; there is no server component.

Load only what the task needs: this file for orientation and the golden
paths, `docs/` for depth, `skills/` for step-by-step procedures with failure
handling.

## Repository map

| Path | Purpose |
|------|---------|
| `playbooks/` | Entry points. `slurm-cluster.yml` and `k8s-cluster.yml` are the two top-level cluster deploys; subdirectories hold component playbooks. |
| `roles/` | Ansible roles (NVIDIA drivers, container toolkit, DGX software, monitoring, Slurm, storage). |
| `config.example/` | Template configuration. Copy to `config/` and edit; never edit `config.example/` for a deployment. |
| `config/` | Your site configuration and inventory (git-ignored; created by you). |
| `scripts/validation/` | Machine-readable preflight and post-deploy validation. Start here to know if anything worked. |
| `scripts/` | Setup and helper scripts (`setup.sh` installs Ansible and dependencies). |
| `submodules/kubespray` | Kubernetes deployment engine. Must be initialized before Kubernetes work. |
| `docs/` | Topic documentation: `deepops/`, `slurm-cluster/`, `k8s-cluster/`, `container/`, `airgap/`. |
| `skills/` | Reusable agent procedures with preconditions, commands, expected output, and failure branches. |

## First-time setup (once per provisioning machine)

```bash
git submodule update --init --recursive
./scripts/setup.sh                      # installs Ansible + Galaxy dependencies
cp -r config.example config             # then edit config/inventory
python3 scripts/validation/deepops_doctor.py --json   # verify before deploying
```

The doctor must report `"ok": true` (or you must understand every failure)
before you run any cluster playbook. With `--remote` it also proves SSH
reachability to every inventory host.

## Golden path: Slurm GPU cluster

```bash
# inventory groups: slurm-master, slurm-node (see config.example/inventory)
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
python3 scripts/validation/validate_slurm.py --json    # run on a cluster node
```

The validator must report `"ok": true` with `gpu_job_ok: true`. See
`skills/deploy-slurm-cluster/` for the full procedure and failure branches.

## Golden path: Kubernetes GPU cluster

```bash
# inventory groups: kube_control_plane, etcd, kube_node (see config.example/inventory)
ansible-playbook -l k8s_cluster playbooks/k8s-cluster.yml
python3 scripts/validation/validate_k8s.py --json --cuda-smoke
```

The validator must report `"ok": true` with `cuda_smoke_ok: true`. See
`skills/deploy-k8s-gpu-cluster/` for the full procedure and failure branches.

## Rules for operating this repository

1. **Validate, don't assume.** Run the doctor before deploying and the
   matching validator after. A playbook finishing with `failed=0` is not the
   success signal; the validator's `"ok": true` is.
2. **Never run a cluster playbook against an unreviewed inventory.** These
   playbooks install drivers, change container runtimes, and can reboot
   machines. Confirm the inventory lists exactly the intended hosts
   (`ansible-inventory --list`, or the doctor's host count) first.
3. **Driver installs can reboot nodes.** Schedule accordingly; never point a
   first-time deploy at hosts with active users or workloads.
4. **Preview when unsure.** `ansible-playbook --check --diff -l <host>` shows
   most pending changes without applying them (some tasks don't support
   check mode). Use `--limit` to scope any run.
5. **Playbooks are idempotent; reruns are the normal recovery path.** After a
   transient failure (package mirror timeout, network blip), rerun the same
   playbook. A converged rerun reports `changed=0`.
6. **Configuration lives in `config/`, not in role defaults.** Override
   variables in `config/group_vars/`; do not edit roles for site-specific
   values.

## Gotchas that look like failures but are not

- **`nvidia-smi` over SSH reports "No devices were found" on Slurm nodes.**
  DeepOps hides GPUs from ordinary SSH sessions on cluster nodes; GPUs are
  visible inside Slurm jobs. Test with
  `srun --gpus=1 nvidia-smi`, or `validate_slurm.py`, never with bare SSH
  `nvidia-smi`.
- **Ansible fact caching can serve stale facts** when an inventory hostname
  is reused for a different machine or after an OS reinstall. Rerun with
  `--flush-cache`.
- **Open vs proprietary NVIDIA kernel modules matter per GPU generation.**
  Turing and newer support the open kernel modules; older GPUs (e.g. Pascal)
  need `nvidia_driver_ubuntu_use_open_kernel_modules: false`. A wrong choice
  produces `nvidia-smi: No devices were found` after a clean-looking install.
  See `skills/diagnose-driver-install/`.
- **Kubernetes playbooks fail on syntax/imports if `submodules/kubespray` is
  not initialized** — the error mentions missing `kubespray_defaults` roles,
  not submodules. Run `git submodule update --init --recursive`.

## Contributing changes

Run before pushing: `git diff --check`, YAML parse on changed files,
`./scripts/deepops/ansible-lint-roles.sh`, and a focused
`ansible-playbook --syntax-check` for changed playbooks. Public CI runs lint,
setup, and molecule checks on every PR. Deployment-affecting changes need
GPU-backed validation evidence in the PR body.
