Scale-out Universal GPU Cluster Deployment Guide
===

Instructions for deploying a scale-out GPU cluster with Kubernetes

## Overview

**Install Process**

  * Install a supported operating system (Ubuntu/RHEL)
  * Configure system
  * Install Kubernetes

**Requirements**

  * Control system to run the install process
  * One or more servers on which to install Kubernetes
  * Management server (if installing OS via PXE)

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

## Step 2: System Configuration

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh

# Install required Ansible roles
ansible-galaxy install -r requirements.yml
```

_Create server inventory_

```sh
# Specify IP addresses of Kubernetes nodes
./scripts/k8s_inventory.sh 10.0.0.1 10.0.0.2 10.0.0.3

# (optional) Modify `k8s-config/hosts.ini` to configure hosts for specific roles
# 	     Make sure the [etcd] group has an odd number of hosts
```

## Step 3: Kubernetes Installation

_Install Kubernetes_

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-e ansible_user=ubuntu`
ansible-playbook playbooks/k8s-cluster.yml
```

_Test access to Kubernetes cluster is working_

```sh
# You may need to manually run: `sudo cp ./k8s-config/artifacts/kubectl /usr/local/bin`
kubectl get nodes
```

## Additional Documentation

  * [Ansible](ANSIBLE.md)
  * [Kubespray/Kubernetes](KUBERNETES.md)
