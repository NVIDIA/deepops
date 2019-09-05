SlurmPerf Deployment Guide
===

## High-Performance Multi-Node Cluster Deployment Guide

   This guide utilizes a collection of playbooks to configure a cluster, deploy a workload manager, and verify performance.

   It leverages open source tools such as Pyxis and Enroot to optimize Slurm for multi-node Deep Learning jobs beyond the cluster configuration described in the [Slurm Deployment Guide](https://github.com/NVIDIA/deepops/blob/master/docs/slurm-cluster.md). Additional details can be found [here](https://docs.nvidia.com/ngc/multi-node-bert-user-guide).

## Supported Distributions

   These packages have been installed and tested with the following Linux distributions and hardware platforms:

   * [NVIDIA DGX OS 4.1 or greater](https://docs.nvidia.com/dgx/dgx-os-server-release-notes/index.html#dgx-os-server-sw-versions)
   * DGX-1
   * Non-blocking InfiniBand switches with DGX-1s [configured in InfiniBand mode](https://docs.nvidia.com/dgx/dgx1-user-guide/configuring-managing-dgx1.html#switching-from-ethernet-to-infiniband).
   * Persistent network storage with [RAID cache](https://docs.nvidia.com/dgx/bp-dgx/storage.html#storage-nfs-cache-deep-learning) configured on DGX-1s

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

3. Edit the Ansible inventory and group_vars

   Edit the Ansible inventory file and verify connectivity to all nodes.

   Ansible uses an inventory which outlines the servers in the cluster and a set of group variables which playbooks use to customize deployment. The previous step created the `config` directory. It is also advised to copy over the slurm-perf example configuration.
      
   ```sh
   # Copy the slurm-perf config
   cp -rfp ./config/slurm-perf/ ./config

   # Modify the Ansible inventory file
   vi config/inventory
   ```

   Verify the configuration.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u <user>`
   # NOTE:  Save the flags used here for the next several playbooks
   ansible all -a "hostname"
   ```

4. Add or modify user(s) across cluster

   The ansible scripts assume a consistent user which has access to all nodes in the cluster.

   > Note: If a user with the same username, uid, and password exists on each node, skip this step.

   ```sh
   # Comment in the `users` section at the end of `config/group_vars/all.yml`
   # The default user is `nvidia` with password `deepops`
   vi config/group_vars/all.yml
   ```

   Run the user-password playbook to create/modify the user across all nodes.

   ```sh
   # NOTE: To create the user, comment out the `users` var in the playbook
   ansible-playbook playbooks/user-password.yml
   ```

5. Edit the NFS configuration

   Update the NFS configuration.

   DeepOps configures NFS for sharing data and models across the cluster of nodes.

   ```sh
   # Comment in the `nfs_exports` and `nfs_mounts` sections of `config/group_vars/all.yml`
   # Modify configuration as necessary to fit the environment, or just use the defaults
    vi config/group_vars/all.yml
   ```

6. Configure NFS across your cluster

   Run the nfs playbook.

   > Note: This step can be skipped if NFS is already configured

   ```sh
   ansible-playbook playbooks/nfs.yml
   ```

7. Deploy optimized Slurm software using Ansible

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

   If the test is successful you should expect to see output similar tobelow:
   ```
   #
   #                                                     out-of-place                       in-place
   #       size         count    type   redop     time   algbw   busbw  error     time   algbw   busbw  error
   #        (B)    (elements)                     (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
              8             2   float     sum   4849.2    0.00    0.00    N/A   3600.9    0.00    0.00    N/A
             16             4   float     sum   1096.6    0.00    0.00    N/A    128.5    0.00    0.00    N/A
             32             8   float     sum    113.5    0.00    0.00    N/A    102.3    0.00    0.00    N/A
             64            16   float     sum    104.3    0.00    0.00    N/A    105.6    0.00    0.00    N/A
            128            32   float     sum    100.9    0.00    0.00    N/A    107.3    0.00    0.00    N/A
            256            64   float     sum    102.9    0.00    0.00    N/A    103.2    0.00    0.00    N/A
            512           128   float     sum    107.3    0.00    0.01    N/A    106.6    0.00    0.01    N/A
           1024           256   float     sum    111.6    0.01    0.02    N/A    112.9    0.01    0.02    N/A
           2048           512   float     sum    126.5    0.02    0.03    N/A    121.7    0.02    0.03    N/A
           4096          1024   float     sum    149.7    0.03    0.05    N/A    144.5    0.03    0.06    N/A
           8192          2048   float     sum    188.2    0.04    0.09    N/A    180.7    0.05    0.09    N/A
          16384          4096   float     sum    261.5    0.06    0.13    N/A    252.8    0.06    0.13    N/A
          32768          8192   float     sum    273.1    0.12    0.24    N/A    262.0    0.13    0.25    N/A
          65536         16384   float     sum    288.6    0.23    0.45    N/A    278.0    0.24    0.47    N/A
         131072         32768   float     sum    314.7    0.42    0.83    N/A    312.0    0.42    0.84    N/A
         262144         65536   float     sum    12070    0.02    0.04    N/A    10270    0.03    0.05    N/A
         524288        131072   float     sum   1730.0    0.30    0.61    N/A    718.0    0.73    1.46    N/A
        1048576        262144   float     sum   1473.7    0.71    1.42    N/A   1585.8    0.66    1.32    N/A
        2097152        524288   float     sum   1456.1    1.44    2.88    N/A   1334.7    1.57    3.14    N/A
        4194304       1048576   float     sum   1045.4    4.01    8.02    N/A   1421.5    2.95    5.90    N/A
        8388608       2097152   float     sum   1252.3    6.70   13.39    N/A   1334.6    6.29   12.56    N/A
       16777216       4194304   float     sum   1988.2    8.44   16.87    N/A   2541.4    6.60   13.19    N/A
       33554432       8388608   float     sum   2526.3   13.28   26.55    N/A   3053.0   10.99   21.97    N/A
       67108864      16777216   float     sum   4154.2   16.15   32.29    N/A   4185.0   16.04   32.05    N/A
      134217728      33554432   float     sum   6599.6   20.34   40.65    N/A   6313.8   21.26   42.49    N/A
      268435456      67108864   float     sum    11363   23.62   47.22    N/A    11425   23.50   46.96    N/A
      536870912     134217728   float     sum    20441   26.26   52.49    N/A    20454   26.25   52.46    N/A
     1073741824     268435456   float     sum    37664   28.51   56.98    N/A    37374   28.73   57.42    N/A
     2147483648     536870912   float     sum    77821   27.60   55.15    N/A    76900   27.93   55.81    N/A
     4294967296    1073741824   float     sum   123111   34.89   69.73    N/A   123228   34.85   69.66    N/A
     8589934592    2147483648   float     sum   210583   40.79   81.53    N/A   210461   40.81   81.57    N/A
   # Out of bounds values : 0 OK
   # Avg bus bandwidth    : 16.2513
   #
   ```

   > Note: These results validate connectivity and do not necessarily indicate optimal performance. The avg bus bandwidth does not matter much - pay attention to the busbw.

## Using Slurm

  The Slurm cluster is now configured to run high-performance multi-node Deep Learning training jobs.

  For cluster usage review the official [Slurm documentation](https://slurm.schedmd.com/overview.html).

  For examples of how to run BERT multi-node training jobs using this configuration, consult the [Multi-Node BERT User Guide](https://docs.nvidia.com/ngc/multi-node-bert-user-guide/).
