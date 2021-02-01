# NGC-based Docker Containers

This directory contains several Dockerfiles for common Deep Learning and Machine Learning frameworks. These serve as an example for extending NGC Docker images.

By default, most NGC containers start a shell prompt. This is perfect for local development, but has limitations when deploying containers through an AI orchestrator (such as Kubernetes) or AI workflow platform (such as Kubeflow). The Dockerfiles in this folder are designed to start JupyterLab by default, allowing for easier integration into interactive notebook platforms such as Kubeflow and other [DGX Ready Software Partners](https://www.nvidia.com/en-us/data-center/dgx-pod/).

These examples are all based on NGC containers and provide a `Dockerfile-minimal` and `Dockerfile` version. The minimal version has the minimal changes required to deploy a NGC container in Kubeflow. The non-minimal version has a curated set of libraries and packages included that are useful for demos, monitoring, generating graphs, Kubernetes integration, and rendering interactive html5 elements.

Where possible, the package versions in these Dockerfiles are hard-coded to ensure repeatable builds and consistent execution of the included examples and tutorials.

Additional details about NGC can be found [here](http://ngc.nvidia.com/).

Additional details about the Deep Learning Examples can be found [here](https://github.com/NVIDIA/DeepLearningExamples).

## Building Docker Images

To build all example images run:

```sh
./build.sh minimal # For minimal images only
./build.sh # For all images
```

The full images can be built individually by running:

```sh
cd tensorflow
docker build -t tensorflow:deepops-kubeflow .
```

The minimal images can be built individually by running:

```sh
cd rapids
docker build -t rapids:deepops-kubeflow-minimal -f Dockerfile-minimal .
```

After building the docker images locally, they can be pushed to a private Docker registry.

> *Note:* It is a violation of the [NGC EULA](https://ngc.nvidia.com/legal/terms) to host a Docker image based off an NGC image in a public registry. All examples included in this directory should only be hosted in private registries, such as those provided by [NGC](https://docs.nvidia.com/ngc/ngc-private-registry-user-guide/index.html).

## Kubeflow Integration

As of v1.2.0, Kubeflow requires containers to start Jupyter, VSCode, or another web application in order to deploy through Kubeflow Notebooks.

A bare-minimum Dockerfile must define the `FROM`, `ENTRYPOINT`, and `CMD`, similar to below. Note that the `base_url` must be defined for Kubeflow to redirect properly.

```sh
FROM nvcr.io/nvidia/pytorch:20.12-py3

ENTRYPOINT ["/bin/sh"]

CMD ["-c", "jupyter lab  --notebook-dir=/workspace --ip=0.0.0.0 --no-browser --allow-root --port=8888 --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${NB_PREFIX}"]
```
 
As a quick-start, several pre-built Kubeflow containers with end-to-end AI workflow tutorial/demo containers can be found on NGC [here](https://ngc.nvidia.com/catalog/containers?query=%20label%3A%22NPN%22&quickFilter=containers).

## Misc. Notes

* JupyterLab is exposed at port 8888
* Tensorboard is exposed at port 6006
* The RAPIDS container has a different jupyter startup command due to it's use of Conda.
* The `WORKDIR` contains the built-in NGC tutorials and example code. This is /workspace in most cases (`/rapids` for RAPIDS containers).

## Included Frameworks

* [PyTorch](https://ngc.nvidia.com/catalog/containers/nvidia:pytorch)
* [TensorFlow](https://ngc.nvidia.com/catalog/containers/nvidia:tensorflow)
* [RAPIDS](https://ngc.nvidia.com/catalog/containers/nvidia:rapidsai:rapidsai)
