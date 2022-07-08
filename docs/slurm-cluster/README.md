# Slurm Deployment Guide

Instructions for deploying a GPU cluster with Slurm

- [Slurm Deployment Guide](#slurm-deployment-guide)
  - [Requirements](#requirements)
  - [Installation Steps](#installation-steps)
  - [Slurm Validation](#slurm-validation)
  - [Using Slurm](#using-slurm)
  - [Prolog and Epilog](#prolog-and-epilog)
  - [Node Health Check](#node-health-check)
  - [Monitoring Slurm](#monitoring-slurm)
  - [Centralized syslog](#centralized-syslog)
  - [Configuring shared filesystems](#configuring-shared-filesystems)
  - [Installing tools and applications](#installing-tools-and-applications)
  - [Installing Open on Demand](#installing-open-on-demand)
  - [Pyxis, Enroot, and Singularity](#pyxis-enroot-and-singularity)
  - [Large deployments](#large-deployments)

## Requirements

- Control system to run the install process
- One server to act as the Slurm controller/login node
- One or more servers to act as the Slurm compute nodes

## Installation Steps

1. Install a supported operating system on all nodes.

   Install a supported operating system on all servers via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided [OS install container](../pxe).

2. Set up your provisioning machine.

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](../deepops/ansible.md).

   ```bash
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create and edit the Ansible inventory.

   Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the `config` directory.

   Edit the inventory:

   ```bash
   # Edit inventory
   # Add Slurm controller/login host to `slurm-master` group
   # Add Slurm worker/compute hosts to the `slurm-node` groups
   vi config/inventory

   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
   ```

   > Note: Multiple hosts can be added to the `slurm-master` group for high-availability. You must also set
   > `slurm_enable_ha: true` in `config/group_vars/slurm-cluster.yml`. For more information about HA Slurm deployments,
   > see: https://slurm.schedmd.com/quickstart_admin.html#HA

4. Verify the configuration.

   ```bash
   ansible all -m raw -a "hostname"
   ```

5. Install Slurm.

   ```bash
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
   ```

## Slurm Validation

A Slurm validation playbook is provided. Please refer to
"[slurm-validation.yml](../../playbooks/slurm-cluster/slurm-validation.yml)".

The validation playbook will verify that Pyxis and Enroot can run GPU jobs
across all nodes by running NCCL tests. The playbook has the following
default parameters that can be overriden:

```bash
    # String; Container for nccl performance/validation tests. Either docker
    #   tag or can be path to sqsh file.
    base_container: "nvcr.io/nvidia/tensorflow:21.09-tf2-py3"

    # String; Container to be created or one that might exist with nccl tests.
    #   If `compile_nccl_tests` is True, it must be a sqsh file.
    #   If `compile_nccl_tests` is False, it can be a docker tag or sqsh file.
    nccl_tests_container: "${HOME}/enroot_images/nccl_tests_slurm_val.sqsh"

    # Bool; Compile and add NCCL tests to the base_container outputing to
    #   nccl_tests_container (will delete/overwrite if one already exists). If
    #   false assumes nccl_tests_container already has the NCCL tests and uses
    #   the nccl_tests_container.
    compile_nccl_tests: True

    # String; NCCL allreduce test command.
    allreduce_command: "all_reduce_perf -b 1M -e 4G -f 2 -g 1"

    # Int; Number of GPUs per node. DGX-1 and DGX A100 Server have 8 GPUs.
    #   DGX-2 has 16 GPUs.
    num_gpus: 8

    # String; Slurm parition to use
    partition: batch

    # Time string; Time limit for the Slurm job.
    timelimit: "10:00"

    # String; Exports for srun command.
    srun_exports: NCCL_DEBUG=INFO

    # String; Custom srun options.
    srun_options:

    # Int or empty; Number of nodes. If empty uses all idle nodes on the partition.
    num_nodes:

    # Bool; Delete the `nccl_tests_container` after running the playbook, only
    #   if `compile_nccl_tests` is true as well.
    cleanup: False
```

The playbook vars control options for compiling NCCL tests. If the `compile_nccl_tests` is set to True (by default) a new enroot container will be built with NCCL tests. The `base_container` must already have NCCL library and MPI installed. The enroot container is saved to the path set by `nccl_tests_container` var (must be a path to sqsh file).

If one already compiled NCCL tests within a container, then set `compile_nccl_tests` to false, and set the `nccl_tests_container` to the container with NCCL tests (this can be a docker remote container, or local sqsh file).

The default behavior is for the playbook to run multinode allreduce NCCL test on all idle nodes in the batch partition. It is possible to override `num_nodes` and run on fewer nodes or more nodes (to include idle nodes, but the srun command will be in the queue until the nodes become available). The variables are used to formulate the NCCL srun command:

```bash
srun --export={{ srun_exports }} \
   -p {{ partition }} \
   --time {{ timelimit }} \
   -N {{ num_nodes }} \
   --ntasks-per-node={{ num_gpus }} \
   --gpus-per-task=1 \
   --exclusive \
   --mpi=pmi2 \
   --no-container-remap-root \
   --container-image="{{ nccl_tests_container }}" \
   {{ srun_options }} \
   {{ allreduce_command }}
```

Please refer to the following examples and adopt for your environment.

NOTE: This will use Pyxis to download a container.

1. Example to run on all idle nodes with default behavior.

   ```bash
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster/slurm-validation.yml
   ```

   This will create a container "`${HOME}/enroot_images/nccl_tests_slurm_val.sqsh`"
   which has to be manually deleted later if desired.

2. Example to run on 2 nodes with PyTorch base container, use custom location
   for compiled nccl container, disable UCX and HCOLL, then cleanup.

   ```bash
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster/slurm-validation.yml \
     -e '{base_container: nvcr.io/nvidia/pytorch:21.09-py3}' \
     -e '{nccl_tests_container: "${HOME}/enroot_images/nccl_tests_torch_val.sqsh"}' \
     -e '{num_nodes: 2}' \
     -e '{srun_exports: "NCCL_DEBUG=INFO,OMPI_MCA_pml=^ucx,OMPI_MCA_coll=^hcoll"}' \
     -e '{cleanup: True}'
   ```

3. Example to run on 1 node using existing NCCL container from a docker repo.
   ```bash
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster/slurm-validation.yml \
     -e '{nccl_tests_container: deepops/nccl-tests-tf20.06-ubuntu18.04:latest}' \
     -e '{compile_nccl_tests: False}' \
     -e '{num_nodes: 1}'
   ```

Pay attention to the playbook output in the terminal. The NCCL compilation and srun command will be printed. Pyxis and PMI are used with srun for orchestrating containers and multinode MPI. The results of "Out of bounds values" and "Avg bus bandwidth" are printed. The "Out of bounds values" should be 0 otherwise the test is considered FAIL. The bandwidth will vary depending on the network. The NCCL allreduce test results are written out to "`/tmp/nccl_tests.out`" after a successful playbook run. If running NCCL tests fails the error results are saved to "`/tmp/nccl_tests.err`". Refer to these file for detailed analysis.

## Using Slurm

Now that Slurm is installed, try a ["Hello World" example using MPI](../../workloads/examples/slurm/mpi-hello/README.md).

Read through the [slurm usage guide](slurm-usage.md) and [Open OnDemand guide](ood.md) for more information.

## Prolog and Epilog

The default Slurm deployment includes a collection of prolog and epilog scripts that should be modified to suit a particular system.
For more information, see the [prolog/epilog documentation](slurm-prolog-epilog/README.md).

## Node Health Check

The default Slurm deployment includes setting up [Node Health Check](https://github.com/mej/nhc). This tool will run periodically on idle nodes to validate that the hardware and software is set up as expected. Nodes which fail this check will be automatically drained in Slurm to prevent jobs running on potentially broken nodes.

However, the default configuration that is generated by DeepOps is very basic, only checking that CPU, memory, and GPUs are present and that a few essential services are running. To customize this file, you can set the `nhc_config_template` variable to point to your custom file.
The [NHC docs](https://github.com/mej/nhc/blob/master/README.md) go into detail about the configuration language.

If you want to disable NHC completely, you can do so by setting `slurm_install_nhc: no` and un-defining the `slurm_health_check_program` variable.

## Monitoring Slurm

As part of the Slurm installation, Grafana and Prometheus are both deployed.

The services can be reached from the following addresses:

- Grafana: http://\<slurm-master\>:3000
- Prometheus: http://\<slurm-master\>:9090

## Centralized syslog

To enable syslog forwarding from the cluster nodes to the first Slurm controller node, you can set the following variables in your DeepOps configuration:

```
slurm_enable_rsyslog_server: true
slurm_enable_rsyslog_client: true
```

For more information about our syslog forwarding functionality, please see the [centralized syslog guide](../misc/syslog.md).

## Configuring shared filesystems

For information about configuring a shared NFS filesystem on your Slurm cluster, see the documentation on [Slurm and NFS](./slurm-nfs.md).

## Installing tools and applications

You may optionally choose to install a tool for managing additional packages on your Slurm cluster.
See the documentation on [software modules](./software-modules.md) for information on how to set this up.

## Installing Open on Demand

[Open OnDemand](https://openondemand.org/) can be installed by setting the `install_open_ondemand` variable to yes before running the `slurm-cluster.yml` playbook.

## Pyxis, Enroot, and Singularity

[Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) are installed by default and can be disabled by setting `slurm_install_enroot` and `slurm_install_pyxis` to no. Singularity can be installed by setting the `slurm_cluster_install_singularity` variable to yes before running the `slurm-cluster.yml` playbook.

## Large deployments

To minimize the requirements for the cluster management services, DeepOps deploys a single Slurm head node for cluster management, shared filesystems, and user login. However, for larger deployments, it often makes sense to run these functions on multiple separate machines.
For instructions on separating these functions, see the [large deployment guide](./large-deployments.md).
