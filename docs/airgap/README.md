# Air-Gap Support

Documentation for setting up clusters in air-gapped environments

- [Air-Gap Support](#air-gap-support)
  - [Summary](#summary)
  - [Setting up mirrors](#setting-up-mirrors)
  - [Using mirrors to deploy offline](#using-mirrors-to-deploy-offline)
  - [Dependency documentation](#dependency-documentation)

## Introduction 
DeepOps supports a number of configuration values for specifying alternate sources and URLs for downloading software. These configuration values can be used to run DeepOps playbooks in environments without an Internet connection, assuming that the environment has an alternative mirror available to supply this software. We currently don't supply our own automation to set up offline mirrors, but we do provide some basic documentation to illustrate how to set these mirrors up and use them.

## Setting up mirrors

- [Setting up offline mirrors for APT repositories](mirror-apt-repos.md)
- [Setting up offline mirrors for RPM repositories](mirror-rpm-repos.md)
- [Setting up an offline mirror for Docker container images](mirror-docker-images.md)
- [Setting up an offline mirror for HTTP downloads](mirror-http-files.md)

## Using mirrors to deploy offline

- [Deploying the NGC-Ready playbook offline](ngc-ready.md)
- Deploying a Kubernetes cluster offline (TODO)
- Deploying a Slurm cluster offline (TODO)

## Dependency documentation

- [Deploying Kubespray in an offline environment](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/offline-environment.md)
