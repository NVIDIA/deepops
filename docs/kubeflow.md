# Kubeflow

[Kubeflow](https://www.kubeflow.org/docs/) is a K8S native tool that eases the Deep Learning and Machine learning lifecycle.

Kubeflow allows users to request specific resources (such as number of GPUs and CPUs), specify Docker images, and easily launch and develop through Jupyter models. Kubeflow makes it easy to create persistent home directories, mount data volumes, and share notebooks within a team.

Kubeflow also offers a full deep learning [pipeline](https://www.kubeflow.org/docs/pipelines/overview/pipelines-overview/) platform that allows you to run, track, and version experiments. Pipelines can be used to deploy code to production and can include all steps in the training process (data prep, training, tuning, etc.) each done through different Docker images.

Additionally Kubeflow offers [hyper-parameter tuning](https://github.com/kubeflow/katib) options.

Kubeflow is an [open source project](https://github.com/kubeflow/kubeflow) and is regularly evolving and adding [new features](https://github.com/kubeflow/kubeflow/blob/master/ROADMAP.md).

## Installation

Deploy Kubernetes by following the [DeepOps Kubernetes Deployment Guide](kubernetes-cluster.md)

Deploy [Ceph](kubernetes-cluster.md#persistent-storage)

Deploy the [LoadBalancer](ingress.md#on-prem-loadbalancer). This step is not required if you specify the `-x` option, however doing so will not include built-in multi-user support.


Deploy Kubeflow:

```sh
# Deploy
./scripts/k8s_deploy_kubeflow.sh

```

See the [install docs](https://www.kubeflow.org/docs/started/k8s/overview/) for additional install configuration options.

Deploy older version of Kubeflow with built-in NGC support:

```sh
./scripts/k8s_deploy_kubeflow.v0.5.1.sh
```
