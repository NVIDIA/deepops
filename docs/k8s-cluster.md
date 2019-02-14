Kubernetes Cluster Build
===

Minimal step-by-step instructions for deploying a Kubernetes GPU cluster

## Overview

**Install Process**

  * Install a supported operating system (Ubuntu/RHEL)
  * Configure systems (default user, drivers, etc.)
  * Install Kubernetes

**Requirements**

  * Control system to run the install process
  * One or more servers on which to install Kubernetes

## Step 1: Operating System Installation

Install a supported operating system (Ubuntu/RHEL) on all servers via
a 3rd-party solution or utilize the provided OS install container

### OS Install via 3rd-party solutions:

  * [MAAS](https://maas.io/)
  * [Foreman](https://www.theforeman.org/)

### OS Install Container

#### Working with an existing DHCP server

Modify `containers/pxe/docker-compose.yml`

Start the PXE server:

```sh
docker-compose -f containers/pxe/docker-compose.yml up -d pxe-ubuntu
```

#### Working with no existing DHCP server

Modify `containers/pxe/docker-compose.yml`

Modify `containers/pxe/dhcp/dnsmasq.conf`

Start the DHCP and PXE servers:

```sh
docker-compose -f containers/pxe/docker-compose.yml up -d dhcp pxe-ubuntu
```

For more information on PXE installation, see the [docs](PXE.md)

## Step 2: Operating System Configuration

Server configuration is done via Ansible. See the docs for detailed instructions: [ANSIBLE.md](ANSIBLE.md)

The control machine should have [passwordless](ANSIBLE.md#passwordless-configuration-using-ssh-keys) (SSH key) access to each server it will configure.

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh

# Install required Ansible roles
ansible-galaxy install -r requirements.yml
```

_Create server inventory_

```sh
# Copy the default configuration
cp -r config.example config

# Review and edit the inventory file to set IPs/hostnames for servers
cat config/inventory

# Review and edit configuration under config/group_vars/*.yml
cat config/group_vars/all.yml
cat config/group_vars/management.yml
cat config/group_vars/gpu-servers.yml
```

_Configure Servers_

```sh
# If sudo requires a password, add the -K flag

# For servers in the `[management]` group
ansible-playbook playbooks/setup-management-servers.yml

# For servers in the `[gpu-servers]` group
ansible-playbook playbooks/setup-gpu-servers.yml
```

_Check GPU driver was installed correctly_

```sh
# You should see all GPUs listed on all GPU servers
ansible gpu-servers -a 'nvidia-smi -L'
```

## Step 3: Kubernetes installation

Kubernetes is installed via the Kubespray project, which uses Ansible

### Installation

```sh
# Make sure kubespray is up to date
git submodule update --init

# Copy the kubespray default configuration
cp -rfp kubespray/inventory/sample/ k8s-config

# Update Ansible inventory file and configuration with inventory builder
declare -a IPS=(10.0.0.1 10.0.0.2 10.0.0.3)
CONFIG_FILE=k8s-config/hosts.ini python3 kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}

# Modify `k8s-config/hosts.ini` to configure hosts for specific roles
# Make sure the [etcd] group has an odd number of hosts

# Install Kubernetes
ansible-playbook -b kubespray/cluster.yml

# Access the Kubernetes cluster by obtaining the admin user config file
./scripts/setup_remote_k8s.sh

# Test access is working
kubectl get nodes

# Add the GPU device plugin
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v1.11/nvidia-device-plugin.yml
```

For more information on Kubespray, see the [docs](KUBERNETES.md)
