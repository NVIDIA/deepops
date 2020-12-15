Deploying without Internet access
=================================

## Overview

DeepOps can be used to deploy a wide variety of software provided both by NVIDIA and by the open-source community.
Because of this, DeepOps relies heavily on access to external software repositories are accessed over the Internet.

However, this reliance on access to software repositories can make deployments more challenging in environments without an open broadband connection to the Internet.
For example, DeepOps can be challenging to deploy in cases where:

- The data center has limited bandwidth to the Internet so that downloads are slow
- The network environment has a strict firewall that doesn't allow access to most repositories
- Security policies do not permit Internet access from compute nodes
- The network environment is fully disconnected from the Internet (i.e., fully "air gapped")

When deploying software without Internet access, the most common strategy is to set up full or partial mirrors of the external repositories you would normally use to deploy.
You can then configure DeepOps to download software from your local mirrors rather than the external repositories.
In order to facilitate this strategy, DeepOps uses Ansible variables for the source location of all software installs, so that they can easily be overridden with local mirrors.


## Identifying the software you need to mirror

DeepOps has many different options for what software you may choose to deploy, in addition to the wide variety of applications you may wish to use on your cluster.
Because of this, it's difficult to provide a complete list of software to mirror.
The docs linked below will identify some known repositories and downloads, but cannot necessarily cover all possibilities.

In order to identify gaps, we recommend that you perform a test deployment in an environment with Internet access, and identify which repositories and downloads are needed.
This should be done both for DeepOps, and for any additional software you plan to deploy on the cluster.
You can then mirror the relevant software in your offline environment.


## Mirroring remote software repositories 

- OS package repositories
    - [Ubuntu](./ubuntu.md)
    - [RHEL/CentOS](./redhat.md)
- [Setting up MAAS offline](./maas.md)
- [Slurm software](./slurm.md)
- [Kubernetes deployment with Kubespray](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/offline-environment.md)
- [Other container images](./containers.md)
- [Helm repositories](./helm.md)
- [PyPI packages](./pypi.md)


