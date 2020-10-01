Slurm Deployment Guide
===

Instructions for deploying a GPU cluster with Slurm

## Requirements

  * Control system to run the install process
  * One server to act as the Slurm controller/login node
  * One or more servers to act as the Slurm compute nodes

## Installation Steps

1. Install a supported operating system on all nodes. 

   Install a supported operating system on all servers via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided [OS install container](../pxe).

2. Set up your provisioning machine. 

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](../deepops/ansible.md).

   ```sh
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create and edit the Ansible inventory. 

   Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the `config` directory. 
   
   Edit the inventory: 
   
   ```sh
   # Edit inventory
   # Add Slurm controller/login host to `slurm-master` group
   # Add Slurm worker/compute hosts to the `slurm-node` groups
   vi config/inventory
   
   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
   ```

4. Verify the configuration.

   ```sh
   ansible all -m raw -a "hostname"
   ```

5. Install Slurm.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
   ```

6. Verify Pyxis and Enroot can run GPU jobs across all nodes.

  ```sh
  # NOTE: This will use Pyxis to download a container and verify GPU functionality across all compute nodes 
  ansible-playbook -l slurm-cluster playbooks/slurm-validation.yml -e '{num_gpus: 1}'
  ```
## Using Slurm

Now that Slurm is installed, try a ["Hello World" example using MPI](../../examples/slurm/mpi-hello/README.md).


## Monitoring Slurm

As part of the Slurm installation, Grafana and Prometheus are both deployed.

The services can be reached from the following addresses:
* Grafana: http://\<slurm-master\>:3000
* Prometheus: http://\<slurm-master\>:9090


## Configuring shared filesystems

For information about configuring a shared NFS filesystem on your Slurm cluster, see the documentation on [Slurm and NFS](./slurm-nfs.md).


## Installing tools and applications

You may optionally choose to install a tool for managing additional packages on your Slurm cluster.
See the documentation on [software modules](./software-modules.md) for information on how to set this up.


## Installing Open on Demand
[Open OnDemand](https://openondemand.org/) can be installed by setting the `install_open_ondemand` variable to yes before running the `slurm-cluster.yml` playbook.


## Pyxis, Enroot, and Singularity
[Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) are installed by default and can be disabled by setting `slurm_install_enroot` and `slurm_install_pyxis` to no. Singularity can be installed by setting the `slurm_cluster_install_singularity` variable to yes before running the `slurm-cluster.yml` playbook.
