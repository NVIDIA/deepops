Scale-out Universal GPU Cluster Deployment Guide
===

Instructions for deploying a scale-out GPU cluster with Kubernetes

## Overview

**Install Process**

  * Install a supported operating system (Ubuntu/RHEL)
  * Install Kubernetes

**Requirements**

  * Control system to run the install process
  * One or more servers on which to install Kubernetes
  * (Optional) Management server (if installing OS via PXE)

## Step 1: Operating System Installation

Install a supported operating system on all servers via
a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided OS install container.

### OS Install Container

This process should run from a Linux system on the same network segment as the target nodes.

_Install Docker_

```sh
./scripts/install_docker.sh
```

_(Optional) Start DHCP server_

If you have an existing DHCP server, skip this step

```sh
# Modify listen interface, DHCP range, and network gateway IP
docker-compose -f containers/pxe/docker-compose.yml run -d dhcp dnsmasq -d --interface=ens192 --dhcp-range=192.168.1.100,192.168.1.199,7200 --dhcp-option=3,192.168.1.1
```

_(Optional) Configure NAT routing_

If you have an existing network gateway, skip this step

```sh
# Set eth0 and eth1 to your public and private interfaces, respectively
./scripts/setup_nat.sh eth0 eth1
```

_Start PXE server_

```sh
docker-compose -f containers/pxe/docker-compose.yml up -d pxe
```

_Install OS_

Set servers to boot from the network for the next boot only (to avoid re-install loops)
and reboot them to install the OS.

The default credentials are:

  * Username: `ubuntu`
  * Password: `deepops`

For more information on PXE installation, see the [docs](PXE.md)

## Step 2: System Configuration

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh
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

## Additional Components

_Test GPU job_

```sh
kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda:9.0-devel --limits=nvidia.com/gpu=1 -- nvidia-smi
```

_Deploy monitoring_

```sh
./scripts/k8s_deploy_monitoring.sh
```

## Additional Documentation

  * [Ansible](ANSIBLE.md)
  * [Kubespray/Kubernetes](KUBERNETES.md)
