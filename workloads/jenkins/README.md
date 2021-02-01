# Jenkins Files

We have several Jenkinsfiles. There is one that is meant to be a lightweight verification that quickly runs against all PRs.

In addition to that we have several which are meant to run nightly and be more robust checks on functionality to check if dependencies have broken.

## Configuration

GPU resources are configured and requested with the following line. Currently the scripting supports allocating `1` or `2` GPUs nodes each with a single GPU:

```sh
lock(resource: null, label: 'gpu', quantity: 1, variable: 'GPUDATA')
```

## Jenkinsfile

This is the original Jenkinsfile that runs every time a PR is created. It does a quick test to verify:

* K8S deploys
* Slurm Deploys
* Slurm and K8S can run a GPU job
* Deploy monitoring
* Deploy Rook

## Jenkinsfile-nightly

Does all the same as `Jenkinsfile` does in addition to:

* Installs Kubeflow
* Does more robust checks against ceph installation

## Jenkinsfile-multi-nightly  

This does everything `Jenkinsfile-nightly` does in addition to:

* Deploys 3 management nodes
* Deploys 2 GPU nodes
* Runs a multi-node GPU Verification

