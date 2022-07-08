# DeepOps

Infrastructure automation tools for Kubernetes and Slurm clusters with NVIDIA GPUs.

## Table of Contents

- [DeepOps](#deepops)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Releases Notes](#releases-notes)
  - [Deployment Requirements](#deployment-requirements)
    - [Provisioning System](#provisioning-system)
    - [Cluster System](#cluster-system)
    - [Kubernetes](#kubernetes)
    - [Slurm](#slurm)
    - [Hybrid clusters](#hybrid-clusters)
    - [Virtual](#virtual)
  - [Updating DeepOps](#updating-deepops)
  - [Copyright and License](#copyright-and-license)
  - [Issues](#issues)
  - [Contributing](#contributing)

## Overview

The DeepOps project encapsulates best practices in the deployment of GPU server clusters and sharing single powerful nodes (such as [NVIDIA DGX Systems](https://www.nvidia.com/en-us/data-center/dgx-systems/)). DeepOps may also be adapted or used in a modular fashion to match site-specific cluster needs. For example:

- An on-prem data center of NVIDIA DGX servers where DeepOps provides end-to-end capabilities to set up the entire cluster management stack
- An existing cluster running Kubernetes where DeepOps scripts are used to deploy KubeFlow and connect NFS storage
- An existing cluster that needs a resource manager / batch scheduler, where DeepOps is used to install Slurm or Kubernetes
- A single machine where no scheduler is desired, only NVIDIA drivers, Docker, and the NVIDIA Container Runtime

## Releases Notes

Latest release: [DeepOps 22.04 Release](https://github.com/NVIDIA/deepops/releases/tag/22.04)

- Kubernetes Default Components:

  - [kubernetes](https://github.com/kubernetes/kubernetes) v1.22.8
  - [etcd](https://github.com/coreos/etcd) v3.5.0
  - [docker](https://www.docker.com/) v20.10
  - [containerd](https://containerd.io/) v1.5.8
  - [cri-o](http://cri-o.io/) v1.22
  - [calico](https://github.com/projectcalico/calico) v3.20.3
  - [dashboard](https://github.com/kubernetes/dashboard/tree/master) v2.0.3
  - [dashboard metrics scraper](https://github.com/kubernetes-sigs/dashboard-metrics-scraper/tree/master) v1.0.4
  - [nvidia gpu operator](https://github.com/NVIDIA/gpu-operator/tree/master) 1.10.0

- Slurm Default Components:

  - [slurm](https://github.com/SchedMD/slurm/tree/master) 21.08.8-2
  - [Singularity](https://github.com/apptainer/singularity/tree/master) 3.7.3
  - [docker](https://www.docker.com/) v20.10

It is recommended to use the latest release branch for stable code (linked above). All development takes place on the master branch, which is generally [functional](docs/deepops/testing.md) but may change significantly between releases.

## Deployment Requirements

### Provisioning System

The provisioning system is used to orchestrate the running of all playbooks and one will be needed when instantiating Kubernetes or Slurm clusters. Supported operating systems which are tested and supported include:

- NVIDIA DGX OS 4, 5
- Ubuntu 18.04 LTS, 20.04 LTS
- CentOS 7, 8

### Cluster System

The cluster nodes will follow the requirements described by Slurm or Kubernetes. You may also use a cluster node as a provisioning system but it is not required.

- NVIDIA DGX OS 4, 5
- Ubuntu 18.04 LTS, 20.04 LTS
- CentOS 7, 8

You may also install a supported operating system on all servers via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided [OS install container](docs/pxe/minimal-pxe-container.md).

### Kubernetes

Kubernetes (K8s) is an open-source system for automating deployment, scaling, and management of containerized applications. The instantiation of a Kubernetes cluster is done by [Kubespray](submodules/kubespray). Kubespray runs on bare metal and most clouds, using Ansible as its substrate for provisioning and orchestration. For people with familiarity with Ansible, existing Ansible deployments or the desire to run a Kubernetes cluster across multiple platforms, Kubespray is a good choice. Kubespray does generic configuration management tasks from the "OS operators" ansible world, plus some initial K8s clustering (with networking plugins included) and control plane bootstrapping. DeepOps provides additional playbooks for orchestration and optimization of GPU environments.

Consult the [DeepOps Kubernetes Deployment Guide](docs/k8s-cluster/) for instructions on building a GPU-enabled Kubernetes cluster using DeepOps.

For more information on Kubernetes in general, refer to the [official Kubernetes docs](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/).

### Slurm

Slurm is an open-source cluster resource management and job scheduling system that strives to be simple, scalable, portable, fault-tolerant, and interconnect agnostic. Slurm currently has been tested only under Linux.

As a cluster resource manager, Slurm provides three key functions. First, it allocates exclusive and/or non-exclusive access to resources (compute nodes) to users for some duration of time so they can perform work. Second, it provides a framework for starting, executing, and monitoring work (normally a parallel job) on the set of allocated nodes. Finally, it arbitrates conflicting requests for resources by managing a queue of pending work. Slurm cluster instantiation is achieved through [SchedMD](https://slurm.schedmd.com/download.html)

Consult the [DeepOps Slurm Deployment Guide](docs/slurm-cluster/) for instructions on building a GPU-enabled Slurm cluster using DeepOps.

For more information on Slurm in general, refer to the [official Slurm docs](https://slurm.schedmd.com/overview.html).

### Hybrid clusters

**DeepOps does not test or support a configuration where both Kubernetes and Slurm are deployed on the same physical cluster.**

[NVIDIA Bright Cluster Manager](https://www.brightcomputing.com/brightclustermanager) is recommended as an enterprise solution which enables managing multiple workload managers within a single cluster, including Kubernetes, Slurm, Univa Grid Engine, and PBS Pro.

**DeepOps does not test or support a configuration where nodes have a heterogenous OS running.**
Additional modifications are needed if you plan to use unsupported operating systems such as RHEL.

### Virtual

To try DeepOps before deploying it on an actual cluster, a virtualized version of DeepOps may be deployed on a single node using Vagrant. This can be used for testing, adding new features, or configuring DeepOps to meet deployment-specific needs.

Consult the [Virtual DeepOps Deployment Guide](virtual/README.md) to build a GPU-enabled virtual cluster with DeepOps.

## Updating DeepOps

To update from a previous version of DeepOps to a newer release, please consult the [DeepOps Update Guide](docs/deepops/update-deepops.md).

## Copyright and License

This project is released under the [BSD 3-clause license](https://github.com/NVIDIA/deepops/blob/master/LICENSE).

## Issues

NVIDIA DGX customers should file an NVES ticket via [NVIDIA Enterprise Services](https://nvid.nvidia.com/enterpriselogin/).

Otherwise, bugs and feature requests can be made by [filing a GitHub Issue](https://github.com/NVIDIA/deepops/issues/new).

## Contributing

To contribute, please issue a [signed](https://raw.githubusercontent.com/NVIDIA/deepops/master/CONTRIBUTING.md) [pull request](https://help.github.com/articles/using-pull-requests/) against the master branch from a local fork. See the [contribution document](https://raw.githubusercontent.com/NVIDIA/deepops/master/CONTRIBUTING.md) for more information.
