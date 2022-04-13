GPU auto-detection with Slurm and NVML
======================================

By default, DeepOps auto-detects GPUs on each node using a [custom Ansible facts script](https://github.com/NVIDIA/deepops/blob/72fe3a187ceb36c76febb64c0bab484cbae6a451/roles/facts/files/gpus.fact),
and uses this to generate Slurm configuration files such as [`slurm.conf`](https://slurm.schedmd.com/slurm.conf.html) and [`gres.conf`](https://slurm.schedmd.com/gres.conf.html).
This mechanism detects GPUs using only `lspci`, allowing us to generate configuration even if a GPU driver is not present.

The disadvantage to this method is that it generates static configuration files.
This method cannot account for future changes in GPU hardware,
or dynamic GPU configurations such as the use of [NVIDIA Multi-Instance GPU](https://www.nvidia.com/en-us/technologies/multi-instance-gpu/).

Instead of generating the configuration based on `lspci` output, Slurm provides the option of [GPU auto-detection](https://slurm.schedmd.com/gres.conf.html#OPT_AutoDetect)
using the [NVIDIA Management Library](https://developer.nvidia.com/nvidia-management-library-nvml) (NVML).
This method enables Slurm to automatically detect the presence of NVIDIA GPUs, and set up local CPU and network affinity correctly.
However, using this feature requires that the NVIDIA driver and CUDA be installed before building Slurm.


## Turning on NVML auto-detection

To enable NVML auto-detection in DeepOps, set the following variable in your DeepOps configuration:

```
slurm_autodetect_nvml: true
```

If building a new cluster, follow the [Slurm deployment guide](./README.md) to set up your new cluster.

If enabling NVML on an existing cluster, run:

```
ansible-playbook -l slurm-cluster -e '{"slurm_force_rebuild": true}' playbooks/slurm-cluster/slurm.yml
```


## Configuring slurm.conf for heterogeneous configurations

The auto-generated `slurm.conf` provided by DeepOps assumes a uniform GPU configuration across your cluster.
It does not account for multiple types of GPU hardware in the same cluster,
or for multiple different types of MIG instance.

This will result in node configuration lines in `slurm.conf` such as the following:

```
NodeName=node01  Gres=gpu:2     CPUs=2 Sockets=2 CoresPerSocket=1 ThreadsPerCore=1 Procs=2 RealMemory=15208 State=UNKNOWN
```

If you have a non-uniform GPU configuration, and especially if you have multiple types of MIG instance, you may wish to configure Slurm so that you can schedule jobs based on GPU type.
In order to distinguish GPU types, Slurm requires that you specify the number of GPUs of each type expected on the node.
This includes specifying the expected set of MIG instances on each node.

For example, if you have a node with two A100 GPUs, and in which each GPU has one `2g.20gb` and one `1g.10gb` MIG instance configured, then the `slurm.conf` line for this node might be:

```
NodeName=node01  Gres=gpu:1g.10gb:2,gpu:2g.20gb:2     CPUs=2 Sockets=2 CoresPerSocket=1 ThreadsPerCore=1 Procs=2 RealMemory=15208 State=UNKNOWN
```

To configure a custom `slurm.conf` file, instead of using the auto-generated file provided by DeepOps, see the documentation
on [configuring DeepOps](../deepops/configuration.md) and on [using static Slurm configuration](./large-deployments.md#manually-generate-static-files-for-cluster-wide-configuration).
