Deployment Guide
===

## Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
  * [Hardware Requirements](#hardware-requirements)
  * [Software Requirements](#software-requirements)
  * [Network Requirements](#network-requirements)
* [Installation Steps](#installation-steps)
  * [Overview](#installation-overview)
  * [1. Prepare the provisioning node](#1-prepare-the-provisioning-node)
  * [2. Prepare the management node(s)](#2-prepare-the-management-nodes)
  * [3. Deploy Kubernetes to the management node(s)](#3-deploy-kubernetes-to-the-management-nodes)
  * [4. Deploy basic cluster services](#4-deploy-basic-cluster-services)
  * [5. Provision the compute node(s)](#5-provision-the-compute-nodes)
  * [6. Deploy Kubernetes to the compute node(s)](#6-deploy-kubernetes-to-the-compute-nodes)
  * [7. Deploy Slurm](#7-deploy-slurm)
  * [8. Deploy additional services](#8-deploy-additional-services)
* [Cluster Usage](#cluster-usage)
* [Cluster Updates](#cluster-updates)

## Overview

This document is written as a step-by-step guide which should allow for a person with minimal Linux system administration experience to install and configure an entire NVIDIA DGX Server cluster from scratch. More experienced administrators should be able to pick and choose items that may be useful, as it is not required to follow all steps in the guide if existing software or infrastructure is to be used.

This document presents one possible configuration for a DGX cluster. Many other configurations are possible, such as selecting different components for storage, PXE provisioning, or DNS, depending on your choices for your infrastructure. However, the process outlined below should enable you to build a functional, well-supported cluster.

Installation involves first bootstrapping management server(s) with a Kubernetes installation and persistent volume storage using Ceph. Cluster services for provisioning operating systems, monitoring, and mirroring container and package repos are then deployed on Kubernetes. From there, DGX servers are booted and installed with the DGX base OS, and Kubernetes is extended across the entire cluster to facilitate job management. An optional login server can be used to allow users a place to interact with data locally and launch jobs. The Slurm job scheduler can also be installed in parallel with Kubernetes to facilitate easier large-scale training jobs or more traditional HPC workloads.

For more information on deploying DGX in the datacenter, consult the
[DGX Data Center Reference Design Whitepaper](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86)

## Prerequisites

### Hardware Requirements

* Provisioning
  * Laptop or workstation for provisioning/deployment via Ansible
    * Ubuntu 18.04 LTS or RHEL/CentOS 7 installed
  * (optional) One of the management nodes can double as a provisioning node if resources are short
* Management
  * 1 or more CPU-only servers for management
  * 3 or more management servers can be used for high-availability
  * Minimum: 4 CPU cores, 16GB RAM, 100GB hard disk
    * More storage required if storing containers in registry, etc.
    * More RAM required if running more services on kubernetes or using one/few servers
  * Ubuntu 18.04 LTS or RHEL/CentOS 7 installed
* Compute/Workers
  * 1 or more DGX compute nodes
* Cluster Usage
  * (optional) 1 CPU-only server for user job launch, data management, etc.

### Software Requirements

The management server(s) should be pre-installed with Ubuntu 18.04 LTS or RHEL/CentOS 7 before starting the installation steps. If you already have a bare-metal provisioning system, it can be used to install Ubuntu/RHEL on the management server(s). Integrating the DGX Base OS with other bare-metal provisioning systems is outside the scope of this project.

A few software package will be installed on the administrator's provisioning system at the beginning of the configuration step.

### Network Requirements

The DeepOps service container "DGXie" provides DHCP, DNS, and PXE services to the cluster, and will allow you to automatically install the official DGX base OS on DGX servers. If you elect to use this management service, you will need to have a dedicated network segment and subnet which can be controlled by the DHCP server.

## Installation Steps

### Installation Overview

1. Prepare the provisioning node
2. Prepare the management node(s)
3. Deploy Kubernetes to the management node(s)
4. Deploy basic cluster services
5. Provision the compute node(s)
6. Deploy Kubernetes to the compute node(s)
7. Deploy Slurm
8. Deploy additional cluster services

### 1. Prepare the provisioning node

To use DeepOps this repository will need to be downloaded onto the administrator's provisioning system. The `setup.sh` script will then install the following software packages:

* Ansible
* Docker
* Git
* ipmitool
* python-netaddr (required by kubespray)

1. Download the DeepOps repo onto the provisioning system:

   ```sh
   git clone --recursive https://github.com/NVIDIA/deepops.git
   cd deepops
   git submodule update
   ```

   > Note: In Git 2.16.2 or later, use `--recurse-submodules` instead of `--recursive`. If you did a non-recursive clone, you can later run `git submodule update --init --recursive` to pull down submodules

2. Install Ansible and other dependencies (if the below script fails follow the official [Ansible installation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) steps to install version 2.5 or later). For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

   ```sh
   ./scripts/setup.sh
   ```

3. Copy and version control the configuration files. The `config/` directory is ignored by the deepops git repo. Create a seperate git repo to track local configuration changes.

   ```sh
   cp -r config.example/ config/
   cd config/
   git init .
   git add .
   git commit -am 'initial commit' && cd ..
   ```

4. Modify the `config/inventory` file to set the cluster server hostnames, and optional per-host info like IP addresses and network interfaces. The cluster should ideally use DNS, but you can also explicitly set server IP addresses in the inventory file.

   Optional inventory settings:

   * Use the `ansible_host` variable to set alternate IP addresses for servers or for servers which do not have resolvable hostnames
   * Use the `ib_bond_addr` variable to configure the infiniband network adapters with IPoIB in a single bonded interface

5. Configure cluster parameters by modifying the various yaml files in the `config/group_vars` directory. The cluster-wide global config resides in the `all.yml` file, while group-specific options reside in the other files. File names correspond to groups in the inventory file, i.e. `[dgx-servers]` in the inventory file corresponds with `config/group_vars/dgx-servers.yml`.

### 2. Prepare the management node(s)

The configuration assumes a single cpu-only management server, but multiple management servers can be used for high-availability. Ensure that the inventory file is edited accordingly if using more than one management server.

Install the latest version of Ubuntu Server 18.04 LTS on each management server. Be sure to enable SSH and record the user and password used during install.

### 3. Deploy Kubernetes to the management node(s)

Deploy Kubernetes to just the management node(s) using the k8s-cluster playbook:

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l management,localhost -i config/inventory -b playbooks/k8s-cluster.yml
```

Test you can access the kubernetes cluster:

```sh
# You may need to manually run: `sudo cp ./k8s-config/artifacts/kubectl /usr/local/bin`
$ kubectl get nodes
NAME      STATUS    ROLES         AGE       VERSION
mgmt    Ready     master,node   7m        v1.12.4
```

### 4. Deploy basic cluster services

1. Install an ingress controller for the cluster.

   See the [Ingress Guide](ingress.md) for details on how to install and configure ingress.

2. Deploy the internal apt package repository.

   ```sh
   kubectl apply -f services/apt.yml
   ```
   
   Runs on port `30000`: http://mgmt:30000

3. Deploy the internal Docker registry.

   ```sh
   helm repo add stable https://kubernetes-charts.storage.googleapis.com
   helm install --values config/registry.yml stable/docker-registry --version 1.4.3
   ansible-playbook -k ansible/playbooks/docker.yml
   ```
   
   You can check the container registry logs with:

   ```sh
   kubectl logs -l app=docker-registry
   ```
   
   The container registry will be available to nodes in the cluster at `registry.local`. To test, see if you can pull a container remotely and push it to the local registry:

   ```sh
   # pull container image from docker hub
   docker pull busybox:latest

   # tag image for local container registry
   # (you can also get the image ID manually with: docker images)
   docker tag $(docker images -f reference=busybox --format "{{.ID}}") registry.local/busybox

   # push image to local container registry
   docker push registry.local/busybox
   ```
   
4. (Optional) Use DGXie for OS management of DGX servers.

   If you already have DHCP, DNS, or PXE servers you can skip this step.

   Follow the setup, configure, and deploy instructions in the [DGXie Guide](dgxie.md).

5. (Optional) Deploy the NGC Container Replicator

   The NGC container replicator makes offline clones of NGC/DGX container registry images.

   For instructions, see: https://github.com/NVIDIA/ngc-container-replicator#kubernetes-deployment

### 5. Provision the compute node(s)

Provision DGX nodes with the official DGX ISO over PXE boot using DGXie.

> Note: The `scripts/do_ipmi.sh` script has these commands and can be looped over multiple hosts

Disable the DGX IPMI boot device selection 60s timeout, you only need to do this once for each DGX, but it is required:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x03 0x08
```

> Note: The default IPMI username and password is `qct.admin`

Set the DGX to boot from the first disk, using EFI, and to persist the setting:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x05 0xe0 0x08 0x00 0x00 0x00
```

Set the DGX to boot from the network in EFI mode, for the next boot only. If you set the DGX to always boot from the network, they will get stuck in an install loop. The installer should set the system to boot to the first disk via EFI after the install is finished

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> chassis bootdev pxe options=efiboot
```

> Note: If you have manually modified the boot order in the DGX SBIOS, you may need to manually return it to boot from disk by default before running the IPMI commands above to alter the boot order

Power cycle/on the DGX to begin the install process:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> power cycle
```

You can monitor install progress via the Java web console on the BMC or the Serial-over-LAN interface:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> sol activate
```

The DGX install process will take approximately 15 minutes. You can tail the DGXie logs with:

```sh
kubectl logs -f $(kubectl get pod -l app=dgxie -o custom-columns=:metadata.name --no-headers)
```

If your DGX are on an un-routable subnet, uncomment the `ansible_ssh_common_args` variable in the `config/group_vars/dgx-servers.yml` file and __modify__ the IP address to the IP address of the management server with access to the private subnet, i.e.:

```sh
ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p -q ubuntu@192.168.1.1"'
```

Test the connection to the DGX servers via the bastion host (management server). Type the password for `dgxuser` on the DGX when prompted. The default password for `dgxuser` is `DgxUser123`:

```sh
ansible dgx-servers -k -a 'hostname'
```

### 6. Deploy Kubernetes to the compute node(s)

1. Run the same `k8s-cluster` ansible-playbook, but this time, do not limit it to just the management node(s):

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -i config/inventory -b playbooks/k8s-cluster.yml
   ```

2. Verify that the Kubernetes cluster is running. 

   ```sh
   # You may need to manually run: `sudo cp ./k8s-config/artifacts/kubectl /usr/local/bin`
   kubectl get nodes
   ``` 

   Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs. 

   ```sh
   kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
   ```

### 7. Deploy Slurm

Configure `config/inventory` according to which server you wish to be in the Slurm cluster. Then deploy Slurm using the `slurm-cluster` ansible-playbook:

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
```

DGX nodes may appear 'down' in Slurm after install due to rebooting. Set nodes to idle if required:

```sh
sudo scontrol update node=dgx01 state=idle
```

If you are running both Slurm and kubernetes on the same DGX, you may want to reserve the system for kubernetes use only. You can do this with the following command:

```sh
sudo scontrol update node=dgx01 state=drain reason=k8s
```

It is also possible to remove the DGX from kubernetes and reserve the resources only for Slurm or to run a mixed hybrid mode.

Once the DGX compute nodes have been added to Kubernetes and Slurm, you can use the `scripts/doctl.sh` script to manage which scheduler each DGX is allowed to run jobs from.

### 8. Deploy additional services

Deploy additional (optional) components on top of Kubernetes by following the [Optional Components](kubernetes-cluster.md#optional-components) section of the Kubernetes Cluster Guide.

Strongly recommended additional services for DGX Pod:
* Persistent Storage
* Monitoring
* Logging

## Cluster Usage

Refer to the following guides for examples of how to use the cluster:
* [Kubernetes Usage Guide](kubernetes-usage.md)
* [Slurm "Hello World" MPI Example](../examples/slurm-mpi-hello/README.md)

## Cluster Updates

Refer to the [DeepOps Update Guide](update-deepops.md) for instructions on how to update the cluster to a new release of DeepOps.
