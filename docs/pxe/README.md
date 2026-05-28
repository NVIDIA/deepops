# OS provisioning via PXE

- [OS provisioning via PXE](#os-provisioning-via-pxe)
  - [Summary](#summary)

## Introduction

Deploying bare-metal clusters at scale generally involves some method for installing the operating system over the network.
This is typically using the [Preboot eXecution Environment (PXE)](https://en.wikipedia.org/wiki/Preboot_Execution_Environment),
a standardized environment which boots an OS from the network.

There are a wide variety of tools for managing OS installation over the network.
Most of the playbooks in DeepOps are agnostic to the OS install tooling, assuming that an OS is already present.
For example, DeepOps can be used to deploy a [Slurm cluster](../slurm-cluster/) or a [Kubernetes cluster](../k8s-cluster) regardless of how the OS was installed.
This makes it relatively easy to integrate with an existing datacenter environment.

DeepOps does not try to replace a site provisioning system.
For environments without an existing bare-metal provisioning workflow, DeepOps provides MAAS setup guidance:

- [MAAS](./maas.md), an open-source bare-metal provisioning tool developed by [Canonical](https://canonical.com/)

For new Ubuntu 24.04 or DGX OS 7 cluster deployments, prefer MAAS, an existing site provisioning system, or Ubuntu autoinstall/cloud-init.
NVIDIA DGX OS 7 supports installing the DGX Software Stack on regular Ubuntu 24.04 for cluster deployments, which is a better fit for current automated installation tooling than the retired legacy DGX OS installer workflows.
