High-Performance Multi-Node Cluster Deployment Guide
===

## Overview

   This guide utilizes a collection of playbooks to configure a cluster, deploy a workload manager, and verify performance.

   It leverages open source tools such as Pyxis and Enroot to optimize Slurm for multi-node Deep Learning jobs beyond the cluster configuration described in the [DeepOps Slurm Deployment Guide](/docs/slurm-cluster.md). Additional details can be found [here](https://docs.nvidia.com/ngc/multi-node-bert-user-guide).

## Supported Distributions

   These packages have been installed and tested with the following Linux distributions and hardware platforms:

   * [NVIDIA DGX OS 4.4 or greater](https://docs.nvidia.com/dgx/dgx-os-server-release-notes/index.html#dgx-os-server-sw-versions)
   * DGX A100
   * Non-blocking InfiniBand switches with the DGX A100s [configured in InfiniBand mode](https://docs.nvidia.com/dgx/dgx1-user-guide/configuring-managing-dgx1.html#switching-from-ethernet-to-infiniband).
   * Persistent network storage with [RAID cache](https://docs.nvidia.com/dgx/bp-dgx/storage.html#storage-nfs-cache-deep-learning) configured on DGX A100s

## Requirements

   * 1 or more DGX servers (Worker nodes)
   * 1 Server or laptop (Ansible provisioning machine)
   * 1 Server or VM (Login node & Slurm controller)
   * 1 or more NFS Servers (Could be the login node or one of the workers)
   * Optional, 1 Server or VM (PXE provisioning machine)
   * Internet access
   * An ssh user that can be used to execute Slurm jobs, has sudo access, and can login to all hosts

## Installation Steps

1. Install a supported operating system on all nodes.

   Install a supported operating system on all servers utilizing the [DGXie](/docs/pxe/dgxie-container.md) provisioning container, via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)), or server BMC/console.

   > NOTE: During OS installation, it is ideal if the identical user/password is configured. Otherwise, follow step 4 below to create an idential user across all nodes in the cluster.

2. Set up your provisioning machine.

   Install Ansible and required software on the provisioning machine.

   DeepOps uses a single provisioning machine to deploy all other software to the cluster. This process may take several minutes as ansible-galaxy roles are downloaded and python packages are installed. For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

   ```sh
   # Install software prerequisites and copy default configuration
   # Copies ./config.example to ./config, if none exists
   ./scripts/setup.sh
   ```

3. Edit the Ansible inventory

   Edit the Ansible inventory file and verify connectivity to all nodes.

   Ansible uses an inventory which outlines the servers in the cluster and a set of group variables which playbooks use to customize deployment. Running `./scripts/setup.sh` in the previous step should have created the `config` directory.
      
   ```sh
   # Modify the Ansible inventory file
   # Especially the `all` and `slurm` sections
   vi config/inventory
   ```

   > NOTE: Be warned that `/etc/hostname` and `/etc/hosts` on each host will be modified to the name(s) specified in the inventory file, so it is best to use the actual names of the hosts.

   When modifying the inventory, if the hosts are not accessible from the provisioning node by their hostname, supply an an `ansible_host`. For example:

   ```yml
   # in config/inventory...

   [all]
   login-node ansible_host_192.168.2.100
   worker-node-01 ansible_host=192.168.2.1
   worker-node-02 ansible_host=192.168.2.2

   ...

   [slurm-master]
   login-node

   [slurm-node]
   worker-node-01
   worker-node-02

   ```

4. Add or modify user(s) across cluster

   The ansible scripts assume a consistent user which has access to all nodes in the cluster.

   > Note: If a user with the same username, uid, and password exists on each node, skip this step. It is critical for the user to exist with the same uid across all nodes.

   ```sh
   # The default user is `nvidia` with password `deepops`
   # Modify this user/password as desired
   vi config/group_vars/all.yml
   ```

   Run the users playbook to create/modify the user across all nodes.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u <user>`
   ansible-playbook -b playbooks/generic/users.yml
   ```

5. Verify the configuration

   ```sh
   ansible all -m raw -a "hostname"
   ```

6. Edit the NFS configuration

   Update the NFS configuration.

   DeepOps configures NFS for sharing data and models across the cluster of nodes. NFS, or some sort of shared storage is important for multi-node deployments so that training data is accessible from all nodes.

   ```sh
   # Comment in the `nfs_exports` and `nfs_mounts` sections of `config/group_vars/all.yml`
   # Modify configuration as necessary to fit the environment, or just use the defaults
   vi config/group_vars/all.yml
   ```

7. Configure NFS across your cluster

   Run the nfs playbooks.

   > Note: This step can be skipped if NFS is already configured

   ```sh
   # NOTE: If SSH user is different than current user, add: `-u <user>`

   # create the NFS server (if not using an existing NFS server)
   ansible-playbook playbooks/generic/nfs-server.yml

   # mount the NFS shares to the clients
   ansible-playbook playbooks/generic/nfs-client.yml
   ```

8. Deploy optimized Slurm software using Ansible

   Run the cluster playbook.

   The `slurm-cluster.yml` playbook bootstraps the cluster, configures NFS, builds slurm & dependencies, and installs it. With the additional variables `slurm_install_enroot` and `slurm_install_pyxis`, it also installs enroot and pyxis.

   ```sh
   # NOTE: If SSH user is different than current user, add: `-u <user>`
   ansible-playbook playbooks/slurm-cluster.yml -e "slurm_install_enroot=true slurm_install_pyxis=true"
   ```

## Performance Validation

   The `slurm-validation.yml` playbook connects to the login node and executes the NCCL tests against all nodes and GPUs. This checks both the correctness and the performance of the cluster. For a full explanation of what these tests do and what the [results mean](https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md) see the official [NCCL Tests documentation](https://github.com/NVIDIA/nccl-tests).

   ```sh
   # Verify Slurm connectivity across all nodes
   ansible-playbook playbooks/slurm-cluster/slurm-validation.yml
   ```

   If the test is successful you should expect to see output similar to that below (run on a cluster of 4x DGX A100 nodes):

   ```
   #
   #                                                     out-of-place                       in-place          
   #       size         count    type   redop     time   algbw   busbw  error     time   algbw   busbw  error
   #        (B)    (elements)                     (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
        1048576        262144   float     sum    135.3    7.75   15.02  7e-07    132.7    7.90   15.31  7e-07
        2097152        524288   float     sum    161.5   12.98   25.15  7e-07    161.3   13.00   25.18  7e-07
        4194304       1048576   float     sum    228.7   18.34   35.53  7e-07    226.9   18.48   35.81  7e-07
        8388608       2097152   float     sum    320.3   26.19   50.75  1e-06    313.7   26.74   51.80  1e-06
       16777216       4194304   float     sum    381.0   44.04   85.32  1e-06    381.6   43.97   85.19  1e-06
       33554432       8388608   float     sum    586.2   57.24  110.90  1e-06    581.3   57.72  111.84  1e-06
       67108864      16777216   float     sum   1079.5   62.16  120.44  1e-06   1080.6   62.11  120.33  1e-06
      134217728      33554432   float     sum   2281.2   58.84  114.00  1e-06   2137.8   62.78  121.64  1e-06
      268435456      67108864   float     sum   3083.1   87.07  168.69  1e-06   3129.9   85.76  166.17  1e-06
      536870912     134217728   float     sum   5657.1   94.90  183.87  1e-06   6000.6   89.47  173.35  1e-06
     1073741824     268435456   float     sum    11643   92.23  178.69  1e-06    11069   97.00  187.94  1e-06
     2147483648     536870912   float     sum    21874   98.18  190.22  1e-06    21929   97.93  189.74  1e-06
     4294967296    1073741824   float     sum    43557   98.61  191.05  1e-06    43440   98.87  191.56  1e-06
   # Out of bounds values : 0 OK
   # Avg bus bandwidth    : 113.289 
   #
   ```

   > Note: These results validate connectivity and do not necessarily indicate optimal performance. The avg bus bandwidth does not matter much - pay attention to the `out-of-place busbw`. DGX A100 has 8x ConnectX-6 Mellanox InfiniBand cards to maintain consistency with internal NVSwitch/NVLink bandwidth. Maximal transfer rates can be close to 200 GB/s. The example above has an out-of-place busbw of 191.05 GB/s, which is in line with what we would expect for DGX A100 nodes networked with InfiniBand. For more background, see the following [blog post](https://devblogs.nvidia.com/scaling-deep-learning-training-nccl/). 

## Using Slurm

   The Slurm cluster is now configured to run high-performance multi-node Deep Learning training jobs.

   For cluster usage review the official [Slurm documentation](https://slurm.schedmd.com/overview.html).

   For examples of how to run BERT multi-node training jobs using this configuration, consult the [Multi-Node BERT User Guide](https://docs.nvidia.com/ngc/multi-node-bert-user-guide/).

## Troubleshooting

### Setup.sh fails due to unsupported ansible version

   DeepOps requires Ansible v2.7.8 or greater. If the setup.sh script fails to achieve this, the latest version of ansible can be installed via pip...

   ```sh
   # on the provisioning node
   sudo pip install ansible=="2.7.11"
   ```

### Connection to hosts via ansible refused/blocked

   By default, fail2ban is running on NVIDIA DGX-1 and DGX-2 servers. Stopping fail2ban during deployment can facilitate setup...

   ```sh
   # on each dgx node
   sudo systemctl stop fail2ban
   ```

### Performance validation test hangs / timeouts

   The last step of the deployment runs a validation test across all nodes and GPUs in the cluster. If this test appears to hang for longer than a few minutes or timeouts completely, it is helpful to diagnose issues that might be occurring directly from the slurm login node...

   ```sh
   # on the slurm login node

   # show running processes
   sinfo

   # show potential issues
   sinfo -R
   ```

   If errors are noticed when running `sinfo -R`, it's also helpful to search the logs for errors on the offending worker node(s)...

   ```sh
   # on the offending worker node(s)
   sudo journalctl -e | grep slurm
   ```

   To re-run the test manually, from the slurm login node...

   ```sh
   # on the slurm login node

   # look up the running job
   squeue

   # cancel it
   scancel <job_id>

   # reset the node states
   sudo scontrol update nodename=<node_names> state=idle

   # run the test again
   srun -N <num_nodes> --mpi=pmix --exclusive --container-image=deepops/nccl-tests-tf20.06-ubuntu18.04 --ntasks-per-node=8 -G <num_nodes x num_gpus_per_node> all_reduce_perf -b 1M -e 4G -f 2 -g <num_gpus_per_node>
   ```

### Performance validation test results are suboptimal

   If the validation test runs, but results are suboptimal, there are many factors that could affect this. Besides hardware and cabling issues, ensure the following...

   ```sh
   # nv_peer_mem should be running
   $ lsmod | grep nv
   nv_peer_mem            16384  0

   # if it isn't, run the following command on each node
   $ sudo modprobe nv_peer_mem
   ```

   Try running the test from the slurm login node, but with debug output enabled...

   ```sh
   # from the slurm login node
   $ NCCL_DEBUG=INFO srun -N <num_nodes> --mpi=pmix --exclusive --container-image=deepops/nccl-tests-tf20.06-ubuntu18.04 --ntasks-per-node=8 -G <num_nodes x num_gpus_per_node> all_reduce_perf -b 1M -e 4G -f 2 -g <num_gpus_per_node>

   # examine the output, looking for any mention of `GDRDMA`
   # for example: `NET/IB/0/GDRDMA`
   # if this is not in the output, it is likely that something is misconfigured in the software
   # if this is in the output, and performance is still low, it is likely that this is a hardware issue
   ```
