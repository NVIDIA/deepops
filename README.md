<img alt="DeepOps" src="docs/deep-ops.svg" width="200">

DeepOps
===

GPU infrastructure and automation tools

## Overview

The DeepOps project encapsulates best practices in the deployment of GPU server clusters and sharing single powerful nodes (such as [NVIDIA DGX Systems](https://www.nvidia.com/en-us/data-center/dgx-systems/)). DeepOps can also be adapted or used in a modular fashion to match site-specific cluster needs. For example:

* An on-prem, air-gapped data center of NVIDIA DGX servers where DeepOps provides end-to-end capabilities to set up the entire cluster management stack
* An existing cluster running Kubernetes where DeepOps scripts are used to deploy Kubeflow and connect NFS storage
* An existing cluster that needs a resource manager / batch scheduler, where DeepOps is used to install Slurm, Kubernetes, or a hybrid of both
* A single machine where no scheduler is desired, only NVIDIA drivers, Docker, and the NVIDIA Container Runtime

## Releases

Latest release: [DeepOps 19.03 Release](https://github.com/NVIDIA/deepops/releases/tag/19.03)

It is recommended to use the latest release branch for stable code (linked above). All development takes place on the master branch, which is generally functional but may change significantly between releases.

## Getting Started

For detailed help or guidance, read through our [Getting Started Guide](docs/getting-started.md) or pick one of the deployment options documented below.

## Deployment Options

### Kubernetes

Kubernetes (K8s) is an open-source system for automating deployment, scaling, and management of containerized applications.

Consult the [Kubernetes Guide](docs/kubernetes-cluster.md) for instructions on building a GPU-enabled Kubernetes cluster using DeepOps.

For more information on Kubernetes in general, refer to the [official Kubernetes docs](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/).

### Slurm

Slurm is an open source, fault-tolerant, and highly scalable cluster management and job scheduling system for large and small Linux clusters.

Consult the [Slurm Guide](docs/slurm-cluster.md) for instructions on building a GPU-enabled Slurm cluster using DeepOps.

For more information on Slurm in general, refer to the [official Slurm docs](https://slurm.schedmd.com/overview.html).

### DGX POD Hybrid Cluster

A hybrid cluster with both Kubernetes and Slurm can also be deployed. This is recommended for [DGX POD](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86) and other setups that wish to make maximal use of the cluster.

Consult the [DGX POD Guide](docs/dgx-pod.md) for step-by-step instructions on building a GPU-enabled hybrid cluster using DeepOps.

### Virtual

To try DeepOps before deploying it on an actual cluster, a virtualized version of DeepOps may be deployed on a single node using Vagrant. This can be used for testing, adding new features, or configuring DeepOps to meet deployment-specific needs.

Consult the [Virtual Guide](virtual/README.md) to build a GPU-enabled virtual cluster with DeepOps.

## Updating DeepOps

To update from a previous version of DeepOps to a newer release, please consult the [Update Guide](docs/update-deepops.md).

## Copyright and License

This project is released under the [BSD 3-clause license](https://github.com/NVIDIA/deepops/blob/master/LICENSE).

## Issues

NVIDIA DGX customers should file an NVES ticket via [NVIDIA Enterprise Services](https://nvid.nvidia.com/enterpriselogin/).

Otherwise, bugs and feature requests can be made by [filing a GitHub Issue](issues/new).

## Contributing

To contribute, please issue a [pull request](https://help.github.com/articles/using-pull-requests/) against the master branch from a local fork.

A signed copy of the [Contributor License Agreement](https://raw.githubusercontent.com/NVIDIA/deepops/master/CLA) needs to be provided to <a href="mailto:deepops@nvidia.com">deepops@nvidia.com</a> before any change can be accepted.
