# DeepOps

Infrastructure automation tools for Kubernetes and Slurm clusters with NVIDIA GPUs.

## Table of Contents

- [DeepOps](#deepops)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
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

Latest release: [DeepOps 26.07 Release](https://github.com/NVIDIA/deepops/releases/tag/26.07)

It is recommended to use the latest release branch for stable code (linked above). All development takes place on the master branch, which is generally [functional](docs/deepops/testing.md) but may change significantly between releases.

Operating this repository with an AI agent (or onboarding as a new human)? Start with [AGENTS.md](AGENTS.md) for the golden paths, operating rules, and [machine-readable validation tools](docs/deepops/validation.md), and [skills/](skills/README.md) for step-by-step procedures.

## Deployment Requirements

### Provisioning System

The provisioning system is used to orchestrate the running of all playbooks and one will be needed when instantiating Kubernetes or Slurm clusters. Current release validation focuses on:

- Ubuntu 22.04 LTS and 24.04 LTS
- NVIDIA DGX OS 6 and 7

DeepOps still retains legacy/community-maintained paths for older environments such as DGX OS 4/5, Ubuntu 18.04/20.04, and CentOS 7/8. Treat those paths as compatibility references unless your site validates them for the release you deploy.

### Cluster System

The cluster nodes will follow the requirements described by Slurm or Kubernetes. You may also use a cluster node as a provisioning system but it is not required. Current release validation focuses on:

- Ubuntu 22.04 LTS and 24.04 LTS for generic Kubernetes and Slurm deployments
- NVIDIA DGX OS 6 and 7 for DGX systems
- Red Hat Enterprise Linux / Rocky Linux 8 and 9 for DGX platform software installation through the `nvidia-dgx` role

DeepOps still retains legacy/community-maintained paths for older environments such as DGX OS 4/5, Ubuntu 18.04/20.04, CentOS 7/8, and the historical DGX EL7 stack. Treat those paths as compatibility references unless your site validates them for the release you deploy.

You may also install a supported operating system on all servers via a 3rd-party solution such as [MAAS](https://maas.io/) or [Foreman](https://www.theforeman.org/), or via an existing site-standard automated installer.
For new Ubuntu 24.04 or DGX OS 7 deployments, prefer Ubuntu autoinstall/cloud-init or MAAS and then apply DeepOps roles after the OS is present.
For DGX platform software installation on top of vanilla Ubuntu or Red Hat family operating systems, see the [DGX software stack role guide](docs/deepops/dgx-software-stack.md).

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
The `nvidia-dgx` role can install NVIDIA DGX platform software on supported DGX systems running Red Hat Enterprise Linux / Rocky Linux 8 or 9; broader Kubernetes or Slurm cluster support on RHEL still requires site-specific validation.

### Virtual

To try DeepOps before deploying it on an actual cluster, a virtualized version of DeepOps may be deployed on a single node using Vagrant. This path is useful for learning and local experimentation, but it is a legacy/community-supported lab path and should not be treated as release-grade validation for current GPU clusters.

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
