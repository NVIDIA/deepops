Slurm GPU Cluster Deployment Guide
===

Instructions for deploying a GPU cluster with Slurm

## Step 1: System Configuration

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh
```

_Configure_

```sh
# Copy default inventory and configuration
cp -r config.example config

# Edit inventory
# Add Slurm controller/login host to `login` group
# Add Slurm worker/compute hosts to `gpu-servers` or `dgx-servers` groups
vi config/inventory

# (optional) Modify `config/group_vars/*.yml` to set configuration parameters
```

_Install Slurm_ 

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-e ansible_user=ubuntu`
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
```

After Slurm has been installed, use the `root` user to run the Slurm playbook
(`-e ansible_user=root`) since only the root user and users currently running a Slurm job will be allowed
to SSH to nodes.
