GPU Server Deployment Guide
===

Instructions for deploying standalone GPU servers.

The install process should be run from a separate control system since
GPU driver installation may trigger a reboot.

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh
```

_Create server inventory and configure_

```sh
# Copy default inventory and configuration
cp -r config.example config

# Edit inventory
# Add GPU servers to `gpu-servers` group
vi config/inventory

# (optional) Modify `config/group_vars/*.yml` to set configuration parameters
```

## Step 3: Server Set Up

_Install_

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l gpu-servers playbooks/standalone.yml
```

## Additional Documentation

[Ansible](ANSIBLE.md)
