# Jenkins Files

This directory contains the legacy Jenkins/Vagrant test harness. Current public
pull request checks run through GitHub Actions; do not assume these Jenkins jobs
are authoritative unless maintainers explicitly enable and reference them for a
specific validation run.

We have several Jenkinsfiles. There is one that was meant to be a lightweight verification that quickly runs against all PRs.

In addition to that we have several which were meant to run nightly and be more robust checks on functionality to check if dependencies have broken.

## Configuration

GPU resources are configured and requested with the following line. Currently the scripting supports allocating `1` or `2` GPUs nodes each with a single GPU:

```sh
lock(resource: null, label: 'gpu', quantity: 1, variable: 'GPUDATA')
```

## Jenkinsfile

This is the original Jenkinsfile that ran every time a PR was created. It does a quick test to verify:

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
