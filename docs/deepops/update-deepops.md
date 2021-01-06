Updating DeepOps
===

## Overview

This document details how to upgrade DeepOps to the next release.

## Updating the DeepOps repository

### Update the repository

Each release of DeepOps is a named tag of the Git repository, with versions using the `YY.MM` numbering scheme. So, for example, the March 2019 release of DeepOps is a tag named `19.03`.

If you don’t have a local clone of the DeepOps repository, you should clone one to your local provisioning host.

```sh
git clone https://github.com/NVIDIA/deepops
```

Check out the git tag for the release you’re upgrading to:

```sh
git checkout <YY.MM>
```

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -b with the checkout command again. Example:

```sh
git checkout -b <new-branch-name>
```

If you’ve made local changes to the DeepOps repository in your own branch, you can rebase your branch onto the release to port your changes to the new release. 

```sh
git checkout <your-branch>
git rebase <YY.MM>
```

> Note that if there are any conflicts between your local branch and the release, you will need to resolve those conflicts as part of the rebase process.

### Port your config

The DeepOps configuration files sometimes change from one release to the next. You should compare your existing configuration (usually in the config/ directory) to the example configuration provided by DeepOps (in config.example/) to identify new required parameters or changes in the config structure.

## Component-based upgrade

DeepOps provides a modular toolkit for deploying many different components of a GPU cluster, such as Kubernetes, Slurm, and Ceph. Each release of DeepOps pins a specific set of versions for these components, so updating to the next release will update the versions of the provided components.

Because DeepOps is modular, any given deployment may only include a subset of the available components. You should identify which components of DeepOps you’re currently using, and what parts of your cluster you will need to upgrade.

Unless otherwise specified, components can be upgraded in any order.

### Updating Slurm

DeepOps specifies the Slurm version as part of the Ansible playbook, so we can upgrade Slurm simply by re-running Ansible.

First, run Ansible in check mode to verify the playbook can run successfully.

```sh
ansible-playbook --check -i config/inventory -l slurm-cluster playbooks/slurm-cluster.yml
```

If there are any errors (for example, due to a changed config), identify and fix those issues. Once check mode runs clean, run Ansible to perform the upgrade.

```sh
ansible-playbook --check -i config/inventory -l slurm-cluster playbooks/slurm-cluster.yml
```

### Updating Kubernetes (Kubespray)

DeepOps deploys Kubernetes using Kubespray, an Ansible framework for deploying production-ready Kubernetes clusters. The Kubernetes upgrade process will be specific to the release of Kubespray which is pinned in the new release of DeepOps. Please see the [Kubespray upgrade docs](https://github.com/kubernetes-sigs/kubespray/blob/7d8da8348e095a5f0b160c1e05c4c399d201d1f0/docs/upgrades.md) for instructions to upgrade Kubernetes.

### Updating Helm

The preferred version of Helm for DeepOps is specified as part the install script. To make sure you have the correct version of Helm, just re-run the install script from the root of the repository.

```sh
scripts/k8s/install_helm.sh
```

### Updating Ceph (Rook)

Ceph is installed for DeepOps via [Rook](https://github.com/rook/rook), an orchestration system for deploying storage systems in Kubernetes.

To upgrade to the most recent version of Ceph and Rook, use the following commands:

```sh
helm update
helm search rook		# Find the most recent version of rook
helm upgrade --namespace rook-ceph-system rook-ceph rook-master/rook-ceph --version ${version}
```

For more details on the Ceph upgrade process, please consult the [Rook documentation](https://github.com/rook/rook/blob/master/Documentation/ceph-upgrade.md).
