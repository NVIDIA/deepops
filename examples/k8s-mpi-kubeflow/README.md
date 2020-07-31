# Kubeflow Multinode Example Pipeline with MPIJobs

## Summary

1. Validate the Kubernetes/Kubeflow environment is setup properly for Multi-GPU and Multinode GPU jobs.
2. Configure this Jupyter environment with the tools needed to interact with Kubeflow and Kubernetes.
3. Define and deploy a Kubeflow pipeline to create K8S PersistentVolumes and download/processess an NLP dataset.
4. Define ande deploy a Kubeflow pipeline to create a multi-pod MPIJob to train TransformerXL using the pre-processed data.
5. Poll the MPIJobs for status, inspect the Worker logs, and cleanup all resources.

The example being used mirrors the Getting Started Guide found on [NGC](https://ngc.nvidia.com/catalog/resources/nvidia:transformerxl_for_tensorflow/quickStartGuide).

## Pre-requisites

Before running through this notebook it is assumed that you have installed Kubernetes, Kubeflow, and the MPI Operator.

For initial setup steps see:

1. [Kubernetes Deployment with DeepOps](https://github.com/NVIDIA/deepops/blob/master/docs/kubernetes-cluster.md)
2. [Kubeflow Deployment with DeepOps](https://github.com/NVIDIA/deepops/blob/master/docs/kubeflow.md) (this may include installation of the MPI Operator)
3. [MPI Operator Installation](https://github.com/kubeflow/mpi-operator)

For production multinode workloads it is also recommended to have properly configured networking using RDMA or RoCE, see [here](https://github.com/NVIDIA/deepops/blob/master/docs/roce-perf-k8s.md) for more details.

### Running this notebook

This notebook can be run on any Kubeflow-compatible Jupyter Container (including the default Kubeflow containers) or can be launched on the same node where your Kubernetes cluster is running.

For best results, launch one of the default containers through the Kubeflow Notebook interface.

![kubeflow-notebook.png](kubeflow-notebook.png)

To begin copy the [notebook](multinode-pipeline.ipynb) to your running JupyterLab container.

![jupyter.png](jupyter.png)
