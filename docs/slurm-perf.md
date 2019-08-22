# High-Performance Multi-Node Cluster Deployment Guide
Instructions for deploying an optimized multi-node GPU cluster. This guide utilizes a collection of scripts and playbooks to configure a cluster, deploy a workload manager, and verify performance.

This guide leverages open source tools such as Pyxis and Enroot to optimize Slurm for multi-node Deep Learning jobs beyond the cluster configuration described in the [Slurm Deployment Guide](https://github.com/NVIDIA/deepops/blob/master/docs/slurm-cluster.md). Additional details can be found [here](Link to main docs). 
## Supported Distributions

These packages have been installed and tested with the following Linux distributions and hardware platforms:

* [NVIDIA DGX OS 4.1 or greater](https://docs.nvidia.com/dgx/dgx-os-server-release-notes/index.html#dgx-os-server-sw-versions)
* DGX-1 
* Infiniband equipment with RDMA support
* Persistent network storage
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

See `examples/slurm-perf/config/inventory` for a 10 node example configuration
      
   ```sh
   # Modify the Ansible inventory file
   vi config/inventory
   ```

Verify the configuration.

   ```sh
  # NOTE: If SSH requires a password, add: `-k`
  # NOTE: If sudo on remote machine requires a password, add: `-K`
  # NOTE: If SSH user is different than current user, add: `-u <user>`
  # NOTE:  Save the flags used here for the next several playbooks
   ansible all -a “uptime; hostname”
   ```

4. Edit the NFS configuration file
Update the NFS configuration.

DeepOps configures NFS for sharing data and models across the cluster of nodes.

See `examples/slurm-perf/group_vars/nfs.yml` for an example. 


```sh
   # Modify the `nfs_exports` and `nfs_mounts` sections of `config/group_vars/all.yml`
    vi config/group_vars/all.yml
```
5. Configure NFS across your cluster
Run the nfs playbook.

   ```sh
   ansible-playbook playbooks/nfs.yml"
   ```
   > Note: This step can be skipped if NFS is already configured

6. Deploy optimized Slurm software using Ansible
Run the cluster playbook.

The `slurm-perf-cluster.yml` playbook bootstraps the cluster, configures NFS, installs/optimizes Slurm, and runs a quick system [validation test](##validation).

   ```sh
   ansible-playbook playbooks/slurm-perf-cluster.yml
   ```
## Performance Validation

The `slurm-performance.yml` playbook connects to the login node and executes the NCCL tests against all nodes and GPUs. This checks both the correctness and the performance of the cluster. For a full explanation of what these tests do and what the [results mean](https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md) see the official [NCCL Tests documentation](https://github.com/NVIDIA/nccl-tests).

This playbook can be run standalone, but is run as the last step in the `slurm-perf-cluster.yml`.

```sh
# Verify Slurm connectivity across all nodes
ansible-playbook playbooks/slurm-validation.yml
```

If the test is successful you should expect to see output similar to the below:
```
#                                                     out-of-place                       in-place
#       size         count    type   redop     time   algbw   busbw  error     time   algbw   busbw  error
#        (B)    (elements)                     (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
    1048576        262144   float     sum    192.4    5.45   10.22  5e-07    193.6    5.42   10.16  5e-07
    2097152        524288   float     sum    271.3    7.73   14.50  5e-07    271.3    7.73   14.49  5e-07
    4194304       1048576   float     sum    374.7   11.19   20.99  5e-07    374.1   11.21   21.02  5e-07
    8388608       2097152   float     sum    541.0   15.51   29.07  5e-07    540.1   15.53   29.12  5e-07
   16777216       4194304   float     sum    865.2   19.39   36.36  5e-07    868.4   19.32   36.22  5e-07
   33554432       8388608   float     sum   1535.5   21.85   40.97  5e-07   1535.3   21.86   40.98  5e-07
   67108864      16777216   float     sum   2717.0   24.70   46.31  5e-07   2711.3   24.75   46.41  5e-07
  134217728      33554432   float     sum   5126.1   26.18   49.09  5e-07   5107.8   26.28   49.27  5e-07
  268435456      67108864   float     sum   9663.2   27.78   52.09  5e-07   9676.9   27.74   52.01  5e-07
  536870912     134217728   float     sum    18620   28.83   54.06  5e-07    18732   28.66   53.74  5e-07
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 35.3542
```
   > Note: These results validate connectivity and do not necessarily indicate optimal performance.
## Using Slurm

The Slurm cluster is now configured to run high-performance multi-node Deep Learning training jobs.
For cluster usage review the official [Slurm documentation](https://slurm.schedmd.com/overview.html) for cluster usage.

For examples on training Deep Learning models using single-node, multi-node, or interactive jobs refer to the [example scripts](examples/slurm-perf/).
