NVIDIA DGX Software Stack
=========================


Overview
--------

NVIDIA® DGX™ systems are shipped preinstalled with DGX™ OS, a customized installation of Ubuntu with additional software from NVIDIA to provide a turnkey solution for running AI and analytics workloads.
This offers users a fast on-boarding experience for using DGX systems and keeping them updated with the latest software versions.

The additional software, the NVIDIA DGX Software Stack, provides platform-specific configurations, diagnostic and monitoring tools, and drivers that are required for a stable, tested, and supported OS to run AI, machine learning, and analytics applications on DGX systems.

However, in some cases, you may choose to initially install a "vanilla" base operating system direct from an upstream Linux distributor.
You can then install the DGX Software Stack after the fact in order to get a similar experience to DGX OS.

NVIDIA provides procedures for installing the DGX Stack on two Linux distributions:

* [DGX Software Stack for Ubuntu 20.04 LTS](https://docs.nvidia.com/dgx/dgx-ubuntu-install-guide/index.html)
* [DGX Software for Red Hat Enterprise Linux 7](https://docs.nvidia.com/dgx/dgx-rhel-install-guide/index.html)
* [DGX Software for Red Hat Enterprise Linux 8](https://docs.nvidia.com/dgx/dgx-rhel8-install-guide/index.html)

DeepOps provides an Ansible playbook, `nvidia-dgx-stack.yml`, which automates the process of installing the DGX Software Stack on either Ubuntu 20.04 or RHEL 7.
We don't support RHEL 8 yet with this playbook, but plan to add this functionality ([issue 1120](https://github.com/NVIDIA/deepops/issues/1120)).


Installing the DGX Software Stack
---------------------------------

### Prerequisites

This procedure assumes that you have already installed a supported Linux distribution on the NVIDIA DGX systems of interest.

First, clone the DeepOps repository from Github.
This can be done on one of the DGX systems, but we strongly recommend running this on a separate machine, because the DGX systems will be rebooted during the playbook run.

```
$ git clone -b <deepops-release> https://github.com/NVIDIA/deepops
$ cd deeops
$ ./scripts/setup.sh
```

Then edit the Ansible inventory file to list the DGX systems of interest and their IP addresses.
For example,

```
[all]
dgx01	ansible_host=10.0.0.1
dgx02	ansible_host=10.0.0.2
...
```

### Configuration options

The default configuration of the DGX stack playbook should work out of the box in most cases.
However, several configuration options are available to adjust the behavior of this playbook.

A subset of the most common configuration options are shown below.
For the full list of available variables, see the `[roles/nvidia_dgx_stack/defaults/main.yml](../../roles/nvidia_dgx_stack/defaults/main.yml)` file.

Valid for both RHEL and Ubuntu:

| Variable | Description | Default |
|----------|-------------|---------|
| `dgx_configure_raid_array` | Should the playbook configure the DGX RAID array? | `false` |
| `nvidia_driver_skip_reboot` | Skip the system reboot following driver install | `false` |
| `dgx_full_upgrade` | Perform a full upgrade of all apt packages during the playbook | `false` |
| `dgx_raid_array` | Device path for RAID array, needed if the OS detects it on non-default paths | |

Valid only for Ubuntu:

| Variable | Description | Default |
|----------|-------------|---------|
| `dgx_disable_unattended_upgrades` | Disable Ubuntu unattended upgrades | `true` |
| `dgx_enable_sol` | Enable IPMI serial-over-LAN | `true` |
| `dgx_enable_logrotate` | Enable DGX logrotate policies | `true` |
| `dgx_install_ofed` | Enable installation of NVIDIA Mellanox OFED | `true` |
| `dgx_install_docker` | Enable Docker installation | `true` |
| `dgx_install_nvsm` | Enable installation of NVIDIA System Management tool | `true` |
| `dgx_install_optional` | Enable installation of optional development tools | `true` |
| `dgx_enable_mlnx_pxe` | Automatically enable PXE boot on Mellanox cards | `true` |
| `dgx_disable_srp` | Disable SCSI RDMA Protocol | `true` |
| `dgx_configure_cachefilesd` | Configure cachefilesd service | `true` |
| `dgx_cuda_driver_branch` | Configure the CUDA driver branch to install | `470` |
 

### Running the playbook

```
$ ansible-playbook [--limit dgx01,dgx02,...] playbooks/nvidia-dgx/nvidia-dgx-stack.yml
```

Note that if the CUDA driver is installed or upgraded, the DGX systems will reboot during playbook execution.
