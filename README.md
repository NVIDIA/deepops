DeepOps
===

GPU cluster infrastructure and automation tools

## Overview

The DeepOps project facilitates deployment of GPU servers and multi-node
GPU clusters for Deep Learning and HPC environments, in an on-prem,
optionally air-gapped datacenter or in the cloud.

See the [Deployment Guide](docs/DEPLOYMENT.md) for step-by-step instructions and setup information

For more information on deploying DGX in the datacenter, consult the
[DGX Data Center Reference Design Whitepaper](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86)

## Components:

  * [Operating System Installation](#operating-system-installation)
  * [Operating System Configuration](#operating-system-configuration)
  * [Orchestration Layer Installation](#orchestration-layer-installation)
  * [Application Layer Installation](#application-layer-installation)

## Operating System Installation

DeepOps currently supports Ubuntu and RHEL/CentOS operating systems and should work with
both vanilla installs or custom OS images.

**Installation methods**

  * Manual OS install
  * 3rd-party tools ([MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/), etc.)
  * [Minimal PXE container](docs/PXE.md)
  * [DGXie](docs/DGXIE.md) (DGX OS specific install automation)

## Operating System Configuration

DeepOps uses Ansible for configuration management and automation.

See the [Ansible Guide](docs/ANSIBLE.md) for information on installing and using Ansible

## Orchestration Layer Installation

### Kubernetes

[Kubernetes (k8s)](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/) is an open-source system for automating deployment, scaling, and management of containerized applications.

See the [Kubernetes Guide](docs/KUBERNETES.md) for information on installing and using Kubernetes

### Slurm

[Slurm](https://slurm.schedmd.com/overview.html) is an open source, fault-tolerant, and highly scalable cluster management and job scheduling system for large and small Linux clusters.

See the [Slurm Guide](docs/SLURM.md) for information on installing and using Slurm

## Application Layer Installation
