DeepOps
===

GPU infrastructure and automation tools

## Overview

The DeepOps project facilitates deployment of GPU servers and multi-node
GPU clusters for Deep Learning and HPC environments, in an on-prem,
optionally air-gapped datacenter or in the cloud.

## Deployment Options

### Kubernetes

[Kubernetes (k8s)](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/) is an open-source system for automating deployment, scaling, and management of containerized applications.

See the [Kubernetes Guide](docs/kubernetes-cluster.md) for information on building a GPU-enabled Kubernetes cluster

### Slurm

[Slurm](https://slurm.schedmd.com/overview.html) is an open source, fault-tolerant, and highly scalable cluster management and job scheduling system for large and small Linux clusters.

See the [Slurm Guide](docs/slurm-cluster.md) for information on building a GPU-enabled Slurm cluster

### DGX POD Hybrid Cluster

Hybrid Kubernetes and Slurm DGX cluster based on the DGX POD reference architecture

See the [Deployment Guide](docs/dgx-pod.md) for step-by-step instructions and setup information

For more information on deploying DGX in the datacenter, consult the
[DGX Data Center Reference Design Whitepaper](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86)

### Virtual

Single-node virtual clusters for testing and customization

See the [Virtual Guide](virtual/README.md) for more information

## Copyright and License

This project is released under the [BSD 3-clause license](https://github.com/NVIDIA/deepops/blob/master/LICENSE).

## Issues and Contributing

A signed copy of the [Contributor License Agreement](https://raw.githubusercontent.com/NVIDIA/deepops/master/CLA) needs to be provided to <a href="mailto:deepops@nvidia.com">deepops@nvidia.com</a> before any change can be accepted.

* Please let us know by [filing a new issue](https://github.com/NVIDIA/deepops/issues/new)
* You can contribute by opening a [pull request](https://help.github.com/articles/using-pull-requests/)

