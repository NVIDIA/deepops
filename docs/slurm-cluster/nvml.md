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


## Configuring MIG

NVIDIA Multi-Instance GPU (MIG) is supported on specific NVIDIA GPUs such as the A100 and the A30.
This feature enables the GPU to be split into multiple distinct GPU instances, which are presented to the user as if they were distinct physical GPUs.
This is helpful especially when scheduling applications which do not need a full physical GPU to get good performance.

MIG is managed using the NVIDIA MIG Manager tool.
To install and configure this tool, you can use the [nvidia-mig.yml](../../playbooks/nvidia-software/nvidia-mig.yml) playbook in DeepOps.
For example,

```
ansible-playbook -l slurm-node -e mig_manager_profile="all-1g.10gb" playbooks/nvidia-software/nvidia-mig.yml
```

Where `mig_manager_profile` is a configuration profile for the NVIDIA `mig-parted` tool.

For more information on configuring MIG, see the documentation for [NVIDIA mig-parted](https://github.com/NVIDIA/mig-parted).

### MIG configuration example

#### Deploy the cluster

Performed a test on a small cluster consisting of the following two nodes:

- Generic white-box server running Ubuntu 20.04 for Slurm controller
- DGX A100 running DGX OS 5.2.0 for Slurm compute node

With inventory file:

```
[all]
login01
dgx01

######
# SLURM
######
[slurm-master]
login01

[slurm-nfs]
login01

[slurm-node]
dgx01

[slurm-cache:children]
slurm-master

[slurm-nfs-client:children]
slurm-node

[slurm-metric:children]
slurm-master

[slurm-login:children]
slurm-master

# Single group for the whole cluster
[slurm-cluster:children]
slurm-master
slurm-node
slurm-cache
slurm-nfs
slurm-metric
slurm-login
```

With a default configuration in `config/group_vars/slurm-cluster.yml` except for:

```
slurm_autodetect_nvml: true
mig_manager_profile: all-balanced-a100-80
```

Configured MIG on the DGX A100 by running the following:

```
ansible-playbook -b -l slurm-node playbooks/nvidia-software/nvidia-mig.yml
```

And then we can show that the MIG devices are configured:

```
user@dgx01$ nvidia-smi -L | head -n10
GPU 0: NVIDIA A100-SXM4-80GB (UUID: GPU-8e100991-ce97-6694-b8eb-b8b1ff5053af)
  MIG 3g.40gb     Device  0: (UUID: MIG-dcf43e8e-5d19-5fa8-8b1d-8aaca1e467f0)
  MIG 2g.20gb     Device  1: (UUID: MIG-6b84cf06-0978-530f-bea3-dd6108f98ebf)
  MIG 1g.10gb     Device  2: (UUID: MIG-3fff3a97-95a9-5046-9053-4c0da3d1add7)
  MIG 1g.10gb     Device  3: (UUID: MIG-7a99e994-6607-5d8a-9ab3-ace43cf9bd96)
GPU 1: NVIDIA A100-SXM4-80GB (UUID: GPU-938c4705-98bf-1735-e98b-c2a5872a8022)
  MIG 3g.40gb     Device  0: (UUID: MIG-51872ee5-5410-564e-abd2-27382756d2d4)
  MIG 2g.20gb     Device  1: (UUID: MIG-9af7553b-306e-55b4-a8c7-4cdef4066af4)
  MIG 1g.10gb     Device  2: (UUID: MIG-3407f5e5-83f9-55c0-abe5-0e2259ac50b1)
  MIG 1g.10gb     Device  3: (UUID: MIG-91e26891-6f5b-5ff3-9c66-310e47d6b059)
```

We then deploy a Slurm cluster across the two nodes by running:

```
ansible-playbook -b -l slurm-cluster playbooks/slurm-cluster.yml
```

#### Custom slurm.conf and nhc.conf

Because we are using MIG, we will need to use a custom Slurm config to specify the number and type of MIG instances. To do this, we first copy the `slurm.conf` from the DGX node to our DeepOps repo:

```
$ scp user@dgx01:/etc/slurm/slurm.conf config/files/slurm.conf
$ scp user@dgx01:/etc/nhc/nhc.conf config/files/nhc.conf
```

Edit the `slurm.conf` to specify the GPUs on the node according to our configured MIG instances. Note that because we have 8 physical GPUs on the node, we have 8x 3g.40gb instances, 8x 2g.20gb instances, and 16x 1g.10gb instances:

```
< NodeName=dgx01  Gres=gpu:8     CPUs=256 Sockets=2 CoresPerSocket=64 ThreadsPerCore=2 Procs=128 RealMemory=1960850 State=UNKNOWN
---
> NodeName=dgx01  Gres=gpu:3g.40gb:8,gpu:2g.20gb:8,gpu:1g.10gb:16  CPUs=256 Sockets=2 CoresPerSocket=64 ThreadsPerCore=2 Procs=128 RealMemory=1960850 State=UNKNOWN
```

NHC does not yet support MIG, so we just disable the GPU check:

```
<  dgx01 || check_nv_gpu_count 8
---
> # dgx01 || check_nv_gpu_count 8
```

We edit `config/group_vars/slurm-cluster.yml` to specify our custom files:

```
slurm_conf_template: "../../config/files/slurm.conf"
nhc_config_template: "../../config/files/nhc.conf"
```

Then run Ansible to push this configuration back out to the cluster:

```
ansible-playbook -b -l slurm-cluster playbooks/slurm-cluster/slurm.yml
ansible-playbook -b -l slurm-cluster playbooks/slurm-cluster/nhc.yml
```

#### Testing the resulting config

Verify that Slurm sees the list of expected GPUs:

```
$ scontrol show node dgx01 | grep Gres
   Gres=gpu:3g.40gb:8(S:0-1),gpu:2g.20gb:8(S:0-1),gpu:1g.10gb:16(S:0-1)
```

Run a job on a 3g.40gb instance:

```
$ srun -N1 --gres=gpu:3g.40gb:1 nvidia-smi -L
GPU 0: NVIDIA A100-SXM4-80GB (UUID: GPU-8e100991-ce97-6694-b8eb-b8b1ff5053af)
  MIG 3g.40gb     Device  0: (UUID: MIG-dcf43e8e-5d19-5fa8-8b1d-8aaca1e467f0)
```

Run a job on a 1g.10gb instance:

```
$ srun -N1 --gres=gpu:1g.10gb:1 nvidia-smi -L
GPU 0: NVIDIA A100-SXM4-80GB (UUID: GPU-8e100991-ce97-6694-b8eb-b8b1ff5053af)
  MIG 1g.10gb     Device  0: (UUID: MIG-3fff3a97-95a9-5046-9053-4c0da3d1add7)
```
