Slurm GPU Cluster Deployment Guide
===

Instructions for deploying a GPU cluster with Slurm

## Overview

**Install Process**

  * Install a supported operating system (Ubuntu/RHEL)
  * Install Slurm

**Requirements**

  * Control system to run the install process
  * One server to act as the Slurm controller/login node
  * One or more servers to act as the Slurm compute nodes
  * (Optional) Management server (if installing OS via PXE)

## Step 1: Operating System Installation

Install a supported operating system on all servers via
a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/))
or utilize the provided [OS install container](PXE.md).

## Step 2: System Configuration

_Set up control machine_

```sh
# Install software prerequisites and copy default configuration
./scripts/setup.sh
```

_Edit server inventory and configuration_

```sh
# Edit inventory
# Add Slurm controller/login host to `login` group
# Add Slurm worker/compute hosts to `gpu-servers` or `dgx-servers` groups
vi config/inventory

# (optional) Modify `config/group_vars/*.yml` to set configuration parameters
```

## Step 3: Install Slurm

_Install Slurm_ 

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
```

## Additional Documentation

[Ansible](ANSIBLE.md)
