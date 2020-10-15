RAPIDS with Dask
===

[Dask](https://dask.org) allows distributed computation in Python.
[RAPIDS](https://rapids.ai/) adds gpu acceleration to machine learning.


Dask has tight kubernetes integration that allows you to scale up/down your Dask cluster either from within your python code or using the `kubectl` utility.

## Installation

### Kubeflow

If Kubeflow has already been installed using the [DeepOps Kubeflow Deployment Guide](kubeflow.md) there are no additional K8S setup steps required.

When deploying through Kubeflow, it is necessary to ensure that a proper Docker image, entrypoint, and cmd have been specified; or Kubeflow will not properly start Jupyter and the service will immediately fail. See the [Dask Kubernetes](../examples/k8s/dask-rapids/docker/Dockerfile) Dockerfile for an example.

### Stand-alone

Deploy Kubernetes by following the [DeepOps Kubernetes Deployment Guide](kubernetes-cluster.md)

Deploy the [LoadBalancer](ingress.md#on-prem-loadbalancer)

Deploy Dask:

```sh
# Optionally, Modify chart configuration
vi config/helm/rapids-dask.yml

# Optionally, modify the K8S resources
vi config/k8s/rapids-dask-sa.yml

# Deploy
./scripts/k8s/deploy_rapids_dask.sh
```

> For more configuration options, see: https://github.com/rmccorm4/charts/tree/update-stable-dask/stable/dask
> For more information about scaling dask in kubernetes see the included example notebooks.
