# DGX Software Stack Role

The `nvidia-dgx` role installs NVIDIA DGX platform software on supported DGX
systems after a base operating system has been installed.

This role is intended for DGX hardware only. It checks the system product name
and stops on non-DGX systems.

## Supported Paths

The role has two implementation paths:

| Base OS | DGX software path | Notes |
| ------- | ----------------- | ----- |
| Ubuntu 18.04 | DGX OS 4 legacy packages | Existing legacy role path. |
| Ubuntu 20.04 | DGX OS 5 legacy packages | Existing legacy role path. |
| Ubuntu 22.04 | DGX OS 6 software stack | Uses the official DGX OS 6 repository archive and system-specific packages. |
| Ubuntu 24.04 | DGX OS 7 software stack | Uses the official DGX OS 7 repository archive and unified `nvidia-system-*` packages. |
| Red Hat Enterprise Linux 7 | Legacy DGX EL7 packages | Existing legacy role path. |
| Red Hat Enterprise Linux 8 / Rocky Linux 8 | DGX Software for RHEL 8 | Uses the official NVIDIA repository setup RPM and DGX configuration groups. |
| Red Hat Enterprise Linux 9 / Rocky Linux 9 | DGX Software for RHEL 9 | Uses the official NVIDIA repository setup RPM and DGX configuration groups. |

The EL8 work addresses GitHub issue
[#1120](https://github.com/NVIDIA/deepops/issues/1120).

## Official References

- [Installing DGX Software on Ubuntu](https://docs.nvidia.com/dgx/dgx-os-6-user-guide/installing_on_ubuntu.html)
- [Customizing Ubuntu Installation with DGX Software](https://docs.nvidia.com/dgx/dgx-os-7-user-guide/installing_on_ubuntu.html)
- [DGX Software for Red Hat Enterprise Linux 8 Installation Guide](https://docs.nvidia.com/dgx/dgx-rhel8-install-guide/index.html)
- [DGX Software for Red Hat Enterprise Linux 8 Release Notes](https://docs.nvidia.com/dgx/dgx-rhel8-sw-release-notes/index.html)
- [DGX Software for Red Hat Enterprise Linux 9 User Guide](https://docs.nvidia.com/dgx/dgx-el9-user-guide/index.html)

## Ubuntu 22.04 / DGX OS 6

The role follows the DGX OS 6 guide:

1. Install the DGX repository files from
   `https://repo.download.nvidia.com/baseos/ubuntu/jammy/dgx-repo-files.tgz`.
2. Install the system-specific DGX configuration and tools packages.
3. Install `linux-tools-nvidia` and `nvidia-peermem-loader`.
4. Optionally install the NVIDIA driver, Docker/NVIDIA Container Toolkit, NVSM,
   serial-over-LAN, logrotate, and additional DGX OS administration/development
   packages.

The default driver branch is `550`, matching the DGX OS 6 examples. Override it
when needed:

```yaml
dgx_os6_driver_branch: "580"
```

Disruptive package upgrades are opt-in:

```yaml
dgx_os6_upgrade_packages: true
```

## Red Hat Enterprise Linux 8 and 9

The role follows the official Red Hat DGX software guides:

1. Optionally enable the required Red Hat subscription repositories on RHEL.
   This is skipped automatically on Rocky Linux.
2. Install the NVIDIA DGX repository setup RPM for EL8 or EL9.
3. Install the DGX configuration group for the detected DGX platform.
4. Optionally install the NVIDIA driver module and support packages.
5. Optionally install Docker CE and the NVIDIA Container Runtime group.

The default driver stream uses DKMS on EL8 so current EL8 minor kernels can
build a matching NVIDIA kernel module: `525-dkms` on most EL8 systems,
`535-dkms` on EL8 DGX H100, and `580` on EL9. EL9 NVSwitch systems install the
open-kernel-module stream by default. Override the branch when a validated DGX
release note calls for another stream:

```yaml
dgx_redhat_driver_branch: "580"
```

RHEL subscription repository management is enabled by default only when
`ansible_distribution == 'RedHat'`. Disable it if subscriptions are managed
outside DeepOps:

```yaml
dgx_redhat_manage_subscription_repos: false
```

Disruptive `dnf update --nobest` behavior is opt-in:

```yaml
dgx_redhat_upgrade_packages: true
```

## Ubuntu 24.04 / DGX OS 7

The role follows the DGX OS 7 guide:

1. Install the architecture-specific DGX OS 7 repository archive from
   `https://repo.download.nvidia.com/baseos/ubuntu/noble/`.
2. Install the unified DGX OS 7 metapackages: `nvidia-system-core`,
   `nvidia-system-utils`, and `nvidia-system-extra`.
3. Install `nvidia-system-station` for DGX Station and DGX Spark systems.
4. Install kernel tools and `nvidia-peermem-loader`.
5. Optionally install the Release 580 open GPU kernel module driver packages,
   including Fabric Manager, NVLSM/NVSDM, or IMEX packages for the DGX platform
   that requires them.

Disruptive package upgrades are opt-in:

```yaml
dgx_os7_upgrade_packages: true
```

## Validation

Full validation requires real DGX hardware and access to NVIDIA/OS package
repositories. At minimum, run syntax validation before opening a PR:

```bash
ansible-playbook --syntax-check playbooks/nvidia-dgx/nvidia-dgx.yml
```

On hardware, validate the role with the target OS and DGX model, reboot if the
driver was installed, then verify:

```bash
nvidia-smi
sudo docker run --gpus=all --rm nvcr.io/nvidia/cuda:12.3.2-base-ubuntu22.04 nvidia-smi
```

Use the RHEL UBI CUDA image from the official guide when validating the RHEL
path.
