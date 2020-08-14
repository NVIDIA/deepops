Getting Started
===

## Requirements

* A pre-existing "provisioning" node which can be used to run Ansible and the install scripts
* A cluster to deploy to (potentially a cluster or single server - or a [virtual one](/virtual/README.md))

## Steps

1. Pick a provisioning node to deploy from. This is where the Ansible scripts should be run from and is often a development laptop that has a connection to the target cluster. On this provisioning node, clone the DeepOps repository...

```
git clone https://github.com/NVIDIA/deepops.git
```

2. Checkout a recent release tag. This is an optional step, but if not done, the latest development code will be used, not an official release.

```
cd deepops
git checkout tags/20.08
```

3. Pick one of the [Deployment Options](/README.md#deployment-options) mentioned in the main [README](/README.md), following the installation instructions. For example, if deploying a hybrid cluster, all features of DeepOps may be deployed by following the [DGX POD Hybrid Cluster](dgx-pod.md) guide.

## Modularity

Each of the deployment options in DeepOps is highly modular and does not need to be deployed as-is. It’s strongly encouraged to read through the installation scripts and examine the playbooks to see which components should be disabled or replaced with custom components. Otherwise, the defaults are an opinionated approach to deploying the cluster for that deployment option.

## Scripts

Optional components are included as scripts in the [/scripts](/scripts) directory. They can also be used on an existing cluster that did not use DeepOps. For example, on an existing Kubernetes cluster, the [/scripts/k8s_deploy_kubeflow.sh](/scripts/k8s_deploy_kubeflow.sh) script can be launched to deploy Kubeflow.

## Examples

Examples are included in the [/examples](/examples) directory. Each example starts with the cluster type, so [/examples/k8s-dask-rapids](/examples/k8s-dask-rapids) requires a Kubernetes cluster.

## Docs

The rest of the docs are in the [/docs](/docs) directory.
