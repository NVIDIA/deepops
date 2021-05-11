# Kubernetes Examples

## Kubernetes Services

The [service](./services) directory contains several yaml files that are used to configure example kubernetes services. Many of these yaml files are used by the [deployment scripts](../../../scripts/k8s/) to configure tools such as Grafana, Prometheus, DCGM-Exporter, etc.

## Example workloads

This directory contains several yaml files that can be used to deploy various verification workloads into the cluster. These are meant for quick verification of a platform (Kubeflow, Kubernetes, Docker, etc.). They are not meant to be used as benchmarking tools. For more information on appropriate benchmarking for a GPU cluster visit the NVIDIA Developer Zone [Deep Learning Product Performance page](https://developer.nvidia.com/deep-learning-performance-training-inference).

[NGC](http://ngc.nvidia.com/) contains Docker images for various Deep Learning and Machine Learning frameworks. Many of these images contain example code and can easily be executed locally through Docker or deployed into Kuberenetes through `yaml` files or `kubectl run` commands.

### Local Docker workloads

#### Run a Jupyter Notebook environment - Docker

To launch an interactive TensorFlow notebook run the below command and then access Jupyter from the IP of the machine you ran the command on at http://${local_ip}:30008

```sh
docker run --rm -it --gpus all -p 30008:8888  nvcr.io/nvidia/tensorflow:21.03-tf1-py3  jupyter lab  --notebook-dir=/workspace --ip=0.0.0.0 --no-browser --allow-root --port=8888 --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${NB_PREFIX}
```
> Note: Most NGC containers contain Jupyter, to run another container such as PyTorch swap out `nvidia/tensorflow:20.12-tf1-py3` for another Docker image (`nvcr.io/nvidia/pytorch:20.12-py3`). Most NGC containers provide example notebooks in `/workspace/nvidia-examples`.

#### Run a DL workload - Docker

Verify Docker is running with GPU support by running the below command. This will execute a ResNet training job on synthetic data.

```sh
docker run --rm -it --gpus all nvcr.io/nvidia/tensorflow:21.03-tf1-py3 python /workspace/nvidia-examples/cnn/resnet.py --layers=50 --batch_size=64
```

Expected output, performance will vary:
```sh
     1   1.0    10.2  7.647  8.618 2.00000
    10  10.0   143.2  4.866  5.839 1.62000
    20  20.0  1381.4  0.288  1.266 1.24469
    30  30.0  1384.5  0.276  1.256 0.91877
    40  40.0  1382.8  0.097  1.077 0.64222
    50  50.0  1384.3  0.119  1.097 0.41506
    60  60.0  1380.9  0.025  1.004 0.23728
    70  70.0  1382.6  0.024  1.002 0.10889
    80  80.0  1386.2  0.001  0.978 0.02988
    90  90.0  1073.2  0.000  0.978 0.00025
```
> Note: This was run on a DGX Station. Some the output was omitted.


### Kubernetes workloads

#### Run a Jupyter Notebook environment - Kubernetes

Run the same Jupyter notebook through Kubernetes by running the below commands. After Jupyter is launched it can be accessed through a NodePort on the management machine's IP (http://${mgmt01_ip}:30008):

```sh
kubectl create -f tensorflow-notebook.yml
kubectl wait --timeout=600s --for=condition=Ready  -l app=tensorflow-notebook pod
```

Delete the notebook by running:

```sh
kubectl delete -f tensorflow-notebook.yml
```

#### Run a DL workload - Kubernetes

Run a ResNet training Job in Kubernetes with the below command:

```sh
kubectl create -f tensorflow-job.yml
```

View the results by viewing the Pod logs:

```sh
kubectl logs -f -l controller-uid=$(kubectl get job tensorflow-job -o jsonpath={.metadata.labels.controller-uid})
```
> Note: The results are expected to be the same or similar to the Docker results.

Delete the Job by running:

```sh
kubectl delete -f tensorflow-job.yml
```

#### Run a DL workload with kubectl - Kubernetes

The same ResNet workload can be run with a single `kubectl` command:

```sh
 kubectl run --rm -it --image=nvcr.io/nvidia/tensorflow:21.03-tf1-py3 --limits="nvidia.com/gpu=1" tensorflow-pod -- python /workspace/nvidia-examples/cnn/resnet.py --layers=50 --batch_size=64
```

Alternatively, a bash prompt can be reached by not specifying a command.

```sh
 kubectl run --rm -it --image=nvcr.io/nvidia/tensorflow:21.03-tf1-py3 --limits="nvidia.com/gpu=1" tensorflow-pod
```

#### Run a Multinode deep learning workload - Kubernetes

This requires the MPI Operator to be installed as described in the Kubeflow install [here](../../../docs/k8s-cluster/kubeflow.md#kubeflow) and the official MPI Operator docs [here](https://github.com/kubeflow/mpi-operator/tree/master/).

Run the below kubectl command to create a multinode MPI job.

An MPIJob will launch `M` workers. Each worker will run its own `Pod`, each with `N` GPUs. For most workloads it is appropriate to set `N` to the number of GPUs on a node (i.e. 8 for a DGX-1). Update the values of `M` and `N` in the `tensorflow-mpi-job.yml` YAML file and set the number of processes to be `M` * `N`.

```sh
            command:
            - mpirun
            - -np
            - "4" # The total number of processes (M * N)
...
    Worker:
      # The number of workers (M)
      replicas: 4
...
            resources:
              limits:
                # The number of GPUs per-worker (N)
                nvidia.com/gpu: 1
```

After properly modifying the YAML file, deploy it with:

```sh
kubectl create -f tensorflow-mpi-job.yml
```

To view the results, wait a few moments for the Pods to start and run:

```sh
kubectl logs -f -l job-name=tensorflow-mpi-job-launcher
```

Delete the MPIJob by running:

```sh
kubectl delete -f tensorflow-mpi-job.yml
```

#### Run a Multinode machine learning workload - Kubernetes

[RAPIDS](https://rapids.ai/) is a GPU accelerated machine learning library that can scale to multi-gpu and multi-node in Kubernetes using [dask](https://dask.org/) and [dask kubernetes](https://kubernetes.dask.org/en/latest/).

To run through a basic K8s scaling use case in Kubernetes run the below command and visit the management node IP at http://${mgmt_ip}:30008, then open the `Scaling Dask in Kubernetes.ipynb` notebook (based on a [kubernetes dask usage tutorial](https://github.com/supertetelman/k8s-rapids-dask)).

```sh
kubectl create -f rapids-dask-notebook.yml
kubectl wait --timeout=600s --for=condition=Ready  -l app=rapids-dask-notebook pod
```

Delete the Notebook by running:

```sh
kubectl delete -f rapids-dask-notebook.yml
```

#### Other examples - Kubernetes

##### Run and view the output of a CUDA nbody application:

```sh
kubectl create -f nbody.yml
kubectl wait --timeout=600s --for=condition=Ready  -l app=cuda-nbody pod
kubectl logs -f -l app=cuda-nbody
kubectl delete -f nbody.yml
```

Expected output:

```sh
...

GPU Device 0: "Tesla V100-DGXS-32GB" with compute capability 7.0

> Compute 7.0 CUDA device: [Tesla V100-DGXS-32GB]
number of bodies = 1000192
1000192 bodies, total time for 10 iterations: 18702.180 ms
= 534.902 billion interactions per second
= 10698.048 single-precision GFLOP/s at 20 flops per interaction
```

##### Run a MNIST job with PyTorch:

```sh
kubectl create -f pytorch-job.yml
kubectl wait --timeout=600s --for=condition=Ready  -l job-name=pytorch-job pod
kubectl logs -f -l job-name=pytorch-job
kubectl delete -f pytorch-job.yml
```

Expected output:

```sh
Train Epoch: 4 [55680/60000 (93%)]      Loss: 0.010437
Train Epoch: 4 [56320/60000 (94%)]      Loss: 0.041916
Train Epoch: 4 [56960/60000 (95%)]      Loss: 0.035813
Train Epoch: 4 [57600/60000 (96%)]      Loss: 0.062634
Train Epoch: 4 [58240/60000 (97%)]      Loss: 0.075980
Train Epoch: 4 [58880/60000 (98%)]      Loss: 0.025073
Train Epoch: 4 [59520/60000 (99%)]      Loss: 0.033341

Test set: Average loss: 0.0407, Accuracy: 9866/10000 (99%)
```


### Kubeflow workloads

For example workloads to deploy into Kubeflow see the Kubeflow NGC integration [README](../../../src/containers/ngc/).

Also see the several kubeflow-* folders that contain example Kubeflow pipelines and workloads.
