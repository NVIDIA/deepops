# High-Performance Multi-Node Cluster Deployment Guide
Instructions for deploying an optimized multi-node GPU cluster. This guide utilizes a collection of scripts and playbooks to configure a cluster, deploy a workload manager, and verify performance.

This guide leverages open source tools such as Pyxis and Enroot to optimize Slurm for multi-node Deep Learning jobs beyond the cluster configuration described in the [Slurm Deployment Guide](https://github.com/NVIDIA/deepops/blob/master/docs/slurm-cluster.md). Additional details can be found [here](Link to main docs). 
## Supported Distributions

These packages have been installed and tested with the following Linux distributions and hardware platforms:

[NVIDIA DGX OS 4.1 or greater](https://docs.nvidia.com/dgx/dgx-os-server-release-notes/index.html#dgx-os-server-sw-versions)
DGX-1 
Infiniband enabled networking equipment.
Persistent network storage
## Requirements


* 1 or more DGX servers (Worker nodes)
* 1 Server or laptop (Ephemeral configuration/management machine)
* 1 Server or VM (Login node & Slurm controller)
* 1 or more NFS Servers
* Optional, 1 Server or VM (PXE provisioning machine)
* Internet access
* An ssh user that can be used to execute Slurm jobs, has sudo access, and can login to all hosts
## Installation Steps

1. Install a supported operating system on all nodes.

Install a supported operating system on all servers utilizing the [DGXie](https://github.com/NVIDIA/deepops/blob/master/docs/dgxie-container.md) provisioning container, via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)), or server BMC/console.

2. Set up your provisioning machine.

Install Ansible and required software on the provisioning machine.

DeepOps uses a single provisioning machine to deploy all other software to the cluster. This process may take several minutes as ansible-galaxy roles are downloaded and python packages are installed. For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

   ```sh
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create and edit the Ansible inventory

Edit the Ansible inventory file and verify connectivity to all nodes.

Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example `inventory` configuration to `config/inventory`. 
      
   ```sh
   # Add the hostnames and IPs of all nodes to the [all] section
   # Add the login node hostname to slurm-master section
   # Add the worker node hostnames to the slurm-worker and nfs-client sections
   # Add the NFS hostname to the nfs-server section
   vi config/inventory
   ```

Verify the configuration.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
  # NOTE:  Save the flags used here for the next several playbooks
   ansible all -a “uptime; hostname”
   ```

4. Edit the NFS configuration file
Update the NFS configuration

DeepOps configures NFS for sharing data and models across the cluster of nodes.

```sh
   # Modify `config/group_vars/all.yaml with information about your NFS share and mount points
   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
```


5. Deploy optimized Slurm software using Ansible
Run the cluster playbook.

The `slurmperf-cluster.yml` playbook bootstraps the cluster, configures NFS, and installs/optimizes Slurm. 

   ```sh
   ansible-playbook playbooks/slurmperf-cluster.yml
   ```

6. Verify Performance
Run the performance playbook.

The `slurm-performance.yml` playbook connects to the login node and executes the NCCL tests against all nodes. This checks both the correctness and the performance of the cluster. For a full explanation of what these tests do and what the [results mean](https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md) see the official [NCCL Tests documentation](https://github.com/NVIDIA/nccl-tests).

```sh

# Verify Slurm performance across all nodes
ansible-playbook playbooks/slurm-performance.yml
```
## Using Slurm

The Slurm cluster is now configured to run high-performance multi-node Deep Learning training jobs.
For cluster usage review the official [Slurm documentation](https://slurm.schedmd.com/overview.html) for cluster usage.

For examples on training Deep Learning models using single-node, multi-node, or interactive jobs refer to the [example scripts](examples/slurm-perf/)

