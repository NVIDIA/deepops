# NGC-based Docker Containers

This directory contains several Dockerfiles for common Deep Learning and Machine Learning frameworks. These serve as an example for extending NGC Docker images.

By default, most NGC containers start a shell prompt. These Dockerfiles are designed to start JupyterLab by default, allowing for easier integration into interactive notebook platforms such as Kubeflow.

They also build ontop of the base NGC containers by including additional packages for demos, monitoring, generating graphs, Kubernetes integration, and rendering interactive html5 elements.

Where possible, the package versions in these Dockerfiles are hard-coded to ensure repeatable builds.

Additional details about NGC can be found [here](http://ngc.nvidia.com/).

## Misc. Notes

* JupyterLab is exposed at port 8888
* Tensorboard is exposed at port 6006
* The `WORKDIR` contains the built-in NGC tutorials and example code. This is /workspace in most cases.

## Included Frameworks

* PyTorch
* TensorFlow
* RAPIDS
