# BinderHub

[BinderHub](https://github.com/jupyterhub/binderhub/) allows automatic builds and deployments of Docker containers utilizing JupyterHub and built from git repos.

BinderHub is coupled with JupyterHub. It allows users to build a GitHub repo that specifies requirements for a Docker image based on Dockerfiles, requirements.txt, and other formats. Docker containers are deployed using pieces of the JupyterHub infrastructure and users have a shareable, repeatable, and deployable Jupyter notebook instance to do their DL/ML workloads through. There is tight integration into Kubernetes, but all interactions are done through a GUI and end-users do not need to have any Kubernetes experience.

The default installation works on a single node. Multi-node installations are supported with additional Docker registry configurations as specified in the [BinderHub docs](https://binderhub.readthedocs.io/en/latest/setup-binderhub.html). This can be done using DockerHub or a private registry such as the registry included with the DeepOps install (registry.local by default).


## Installation

Deploy Kubernetes by following the [Kubernetes GPU Cluster Deployment Guide](kubernetes-cluster.md)

Deploy the [LoadBalancer](ingress.md#on-prem-loadbalancer)

Deploy [Ceph](kubernetes-cluster.md#persistent-storage)


Deploy Binderhub:

```sh
# Deploy
./scripts/k8s_deploy_binderhub.sh

```
