Kubernetes GPU Cluster Deployment Guide
===

Instructions for deploying a GPU cluster with Kubernetes

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
a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/))
or utilize the provided [OS install container](PXE.md).

## Step 2: System Configuration

_Set up control machine_

```sh
# Install software prerequisites and copy default configuration
./scripts/setup.sh
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
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -i k8s-config/hosts.ini -b playbooks/k8s-cluster.yml
```

_Test access to Kubernetes cluster is working_

```sh
# You may need to manually run: `sudo cp ./k8s-config/artifacts/kubectl /usr/local/bin`
kubectl get nodes
```

_Test GPU job_

```sh
kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
```

## Step 4: Optional Kubernetes Components

### Kubernetes Dashboard

Run the script to create an administrative user and print out the dashboard URL and access token:

```sh
./scripts/k8s_deploy_dashboard_user.sh
```

### Storage

Ceph cluster running on Kubernetes to provide persistent storage

```sh
./scripts/k8s_deploy_rook.sh
```

### Monitoring

Prometheus and Grafana to monitor Kubernetes and cluster nodes

```sh
./scripts/k8s_deploy_monitoring.sh
```

### Container Registry

The default container registry hostname is `registry.local`. To set another hostname (for example,
one that is resolvable outside the cluster), add `-e container_registry_hostname=registry.example.com`.

```sh
ansible-playbook -i k8s-config/hosts.ini -b --tags container-registry playbooks/k8s-services.yml
```

## Additional Documentation

[Ansible](ANSIBLE.md)

More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

