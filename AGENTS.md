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
| `skills/` | Reusable agent procedures with preconditions, commands, expected output, and failure branches. Index in `skills/README.md`. |
| `tests/` | Host-free regression tests for role scripts that CI cannot exercise (`tests/slurm-epilog/`). |
| `workloads/` | Example jobs, Helm charts, and services to run on a deployed cluster; not part of the deploy. |

Releases are tagged (`26.09` is current). Deploy from the latest release tag;
`master` is the development branch and changes between releases.

## Skills: pick the procedure, then follow it

| Task | Skill |
|------|-------|
| Deploy or rebuild a Slurm GPU cluster | `skills/deploy-slurm-cluster/` |
| Deploy or rebuild a Kubernetes GPU cluster | `skills/deploy-k8s-gpu-cluster/` |
| Provision bare metal or VMs through MAAS, then build inventory from MAAS tags | `skills/provision-with-maas/` |
| Deploy without Internet access (mirrors, transfer, offline validation) | `skills/deploy-airgapped/` |
| Health-check or verify a deployed cluster | `skills/validate-gpu-cluster/` |
| NVIDIA driver failures, `nvidia-smi` errors, GPU pods crash-looping | `skills/diagnose-driver-install/` |

Each skill is self-contained. Read the whole `SKILL.md` before running its
first command; the failure branches are where the time saved is.

## First-time setup (once per provisioning machine)

```bash
git submodule update --init --recursive
./scripts/setup.sh                      # installs Ansible + Galaxy dependencies
cp -r config.example config             # then edit config/inventory
python3 scripts/validation/deepops_doctor.py --json   # verify before deploying
```

`setup.sh` is non-interactive, must run as a regular user with `sudo`
rights (it exits 1 as root), and warns instead of failing on distributions
it does not recognize; a missing `virtualenv` afterwards is the real signal
that dependencies were not installed. Rerunning it is safe.

The doctor must report `"ok": true` (or you must understand every failure)
before you run any cluster playbook. Its local checks cover Ansible, Galaxy
roles, the Kubespray submodule, `config/`, and the inventory (parseable and
populated; each check's `detail` says how to fix it). With
`--remote` it also proves SSH reachability to every inventory host. The
doctor only inspects an inventory when `config/` (or `DEEPOPS_CONFIG_DIR`)
exists, even if you pass `--inventory`.

## Golden path: Slurm GPU cluster

```bash
# inventory groups: slurm-master, slurm-node (see config.example/inventory)
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
python3 scripts/validation/validate_slurm.py --json    # run on a cluster node
```

The validator must report `"ok": true` with `gpu_job_ok: true`. See
`skills/deploy-slurm-cluster/` for the full procedure and failure branches.
Both validators also emit a name-sorted `nodes` list with per-node state and
GPU counts; use it to name the failing node instead of guessing from totals.

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
   (`ansible-inventory --list`, or the doctor's inventory checks) first.
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
- **Enroot downloads 404 on RHEL-family hosts after raising `enroot_version`
  to 3.4.1 or later.** The role still builds `el7` RPM names; override
  `enroot_rpm_packages` with the `el8` artifacts as shown in
  `docs/deepops/update-deepops.md`. Release 3.4.0 cannot be made to work for
  both package families; pick another.
- **Singularity and Open OnDemand are no longer installed by DeepOps** (retired
  in 26.09). Playbooks and variables for them are gone; old `config/` trees
  that still set `slurm_cluster_install_singularity` or `install_open_ondemand`
  are simply ignored.
- **GPU management tasks in the Slurm playbooks run outside the SSH cgroup on
  purpose.** The login GPU guard above would otherwise hide devices from the
  playbook's own `nvidia-smi` calls (MIG, clocks, DCGM); this is expected, not
  a privilege escalation to investigate.

## Contributing changes

Run before pushing: `git diff --check`, YAML parse on changed files,
`./scripts/deepops/ansible-lint-roles.sh`, and a focused
`ansible-playbook --syntax-check` for changed playbooks. Then the test that
matches what you touched:

| Changed | Run |
|---------|-----|
| `scripts/validation/*.py` | `python3 -m unittest discover -s scripts/validation/tests` |
| Slurm prolog/epilog templates under `roles/slurm/templates/etc/slurm/` | `tests/slurm-epilog/run-tests.sh` |
| Any role template (`*.j2`) | `python3 scripts/deepops/check-template-syntax.py` |

Public CI runs ansible-lint, `setup.sh`, molecule role converges, and CodeQL
on every PR. The `slurm` role is excluded from molecule (it needs systemd
services a container cannot run), which is why `tests/slurm-epilog/` exists.
Deployment-affecting changes need GPU-backed validation evidence in the PR
body. Keep skills honest: every command in a `SKILL.md` must work as written
from a clean checkout, and failure branches should come from observed
failures, not speculation.
