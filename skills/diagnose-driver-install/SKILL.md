---
name: diagnose-driver-install
description: Diagnose NVIDIA driver installation failures on DeepOps-managed nodes — nvidia-smi errors, "No devices were found", DKMS build failures, or GPU pods crash-looping. Use before reinstalling anything.
---

# Diagnose an NVIDIA driver install

Work through these in order; most "driver failures" are one of the first
three and need no reinstall.

## 1. Are you being fooled by GPU hiding?

On DeepOps **Slurm** nodes, GPUs are hidden from ordinary SSH sessions by
design. Bare `nvidia-smi` over SSH reporting `No devices were found` on an
otherwise healthy node is expected.

```bash
srun --gpus=1 nvidia-smi          # the authoritative test on Slurm nodes
```

If the srun job sees the GPU, the driver is fine. Stop here.

## 2. Is the hardware visible at all?

```bash
lspci | grep -i nvidia
```

No output → not a driver problem. The GPU is absent, unseated, or bound by
VFIO passthrough or platform firmware; escalate to hardware support before
touching software.

## 3. Open vs proprietary kernel modules

`nvidia-smi: No devices were found` immediately after a clean install is the
classic symptom of the wrong module flavor for the GPU generation:

- Turing and newer (T4, A100, H100, RTX PRO Blackwell): open kernel modules
  supported — DeepOps default `nvidia_driver_ubuntu_use_open_kernel_modules: true`
  is correct.
- Pascal and older (P100, GTX 10xx): open modules are **not** supported —
  set `nvidia_driver_ubuntu_use_open_kernel_modules: false` in
  `config/group_vars/all.yml` and rerun the driver play.

Check what is loaded: `modinfo nvidia | grep -i license` (open modules say
MIT/GPL, proprietary says NVIDIA).

## 4. Did the kernel module actually build and load?

```bash
dkms status                        # driver module state per kernel
dmesg | grep -iE 'nvidia|nvrm' | tail -20
lsmod | grep nvidia
```

- DKMS shows an error for the running kernel → usually missing headers
  (`linux-headers-$(uname -r)`) or a kernel updated after the driver
  install. Install headers or reboot into the matching kernel, then rerun
  the driver play.
- Module loaded but `nvidia-smi` fails → check `dmesg` for RmInitAdapter or
  fallen-off-the-bus errors; these are hardware/firmware territory.

## 5. Rerun the play, don't hand-fix

After correcting configuration, converge with the playbook rather than
manual package surgery, then validate:

```bash
ansible-playbook -l <host> playbooks/nvidia-software/nvidia-driver.yml
python3 scripts/validation/validate_slurm.py --json    # or validate_k8s.py
```

Reruns are idempotent; a healthy converged rerun reports `changed=0`.

## Kubernetes-specific notes

GPU Operator crash-looping driver pods: `kubectl logs -n <gpu-operator
namespace> <driver-pod>` usually names the same root causes — missing
headers, wrong module flavor, or a node reboot needed. Fix via the operator
values or node state, not by installing drivers by hand on the host (the
operator owns the driver on Kubernetes nodes unless DeepOps was configured
for host drivers).
