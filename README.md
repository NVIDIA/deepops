DeepOps
===

GPU infrastructure and automation tools

## Overview

The DeepOps project facilitates deployment of GPU servers and multi-node GPU clusters for Deep Learning and HPC environments, in an on-prem, optionally air-gapped datacenter or in the cloud.

Use the provided Ansible playbooks and scripts to deploy Kubernetes, Slurm, or a hybrid of both. This repository encapsulates best practices to make your life easier, but can also be adapted or used in a modular fashion to suite your specific cluster needs. For example: if your organization already has Kubernetes deployed to a cluster, you can still use the optional services and scripts provided to install Kubeflow, enable authentication, or connect NFS storage.

> NOTE: we recommend using the most recent release branch for stable code.
> The `master` branch is used for development and as such may be unstable or even broken at any point in time.

## Getting Started

Pick one of the deployment options below if you know what kind of cluster you want. If you feel lost, read through our [Getting Started Guide](docs/getting-started.md).

## Deployment Options

### Kubernetes

Kubernetes (K8s) is an open-source system for automating deployment, scaling, and management of containerized applications.

Consult our [Kubernetes Guide](docs/kubernetes-cluster.md) to build a GPU-enabled Kubernetes cluster.

For more information on Kubernetes in general, refer to the [official Kubernetes docs](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/).

### Slurm

Slurm is an open source, fault-tolerant, and highly scalable cluster management and job scheduling system for large and small Linux clusters.

Consult our [Slurm Guide](docs/slurm-cluster.md) to build a GPU-enabled Slurm cluster.

For more information on Slurm in general, refer to the [official Slurm docs](https://slurm.schedmd.com/overview.html).

### DGX POD Hybrid Cluster

A hybrid cluster with both Kubernetes and Slurm can also be deployed. This is recommended for DGX Pod and other setups that wish to make maximal use of the cluster.

Consult our [DGX Pod Guide](docs/dgx-pod.md) for step-by-step instructionson setting up a hybrid cluster.

For more information on deploying DGX in the datacenter, consult the
[DGX Data Center Reference Design Whitepaper](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86)

### Virtual

We often don't have a full cluster at our disposal, or wish to try DeepOps before we deploy it on the actual cluster. For this purpose, a virtualized version of DeepOps may be deployed on a single node. Very useful for testing, adding new features, or configuring DeepOps to meet your specific needs.

Consult our [Virtual Guide](virtual/README.md) to deploy a virtual cluster with DeepOps.

## Updating DeepOps

To update your cluster from a previous version of DeepOps to a newer release, please consult the [Update Guide](docs/updating.md).

## Copyright and License

This project is released under the [BSD 3-clause license](https://github.com/NVIDIA/deepops/blob/master/LICENSE).

## Issues and Contributing

A signed copy of the [Contributor License Agreement](https://raw.githubusercontent.com/NVIDIA/deepops/master/CLA) needs to be provided to <a href="mailto:deepops@nvidia.com">deepops@nvidia.com</a> before any change can be accepted.

* Please let us know by [filing a new issue](https://github.com/NVIDIA/deepops/issues/new)
* You can contribute by opening a [pull request](https://help.github.com/articles/using-pull-requests/)
