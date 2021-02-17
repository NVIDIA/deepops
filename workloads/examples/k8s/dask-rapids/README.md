Running a benchmark with RAPIDS and Dask on Jupyter and Kubernetes
==================================================================

[RAPIDS](https://rapids.ai/) provides a suite of open source software libraries for doing data science on GPUs.
It's often used in conjunction with [Dask](https://dask.org/), a Python framework for running parallel computing jobs.
Both these tools are commonly used to run data science and analytics jobs across large clusters of machines.

In this example, I'll walk through running a simple parallel sum benchmark in a  [Jupyter](https://jupyter.org/) notebook, using RAPIDS for working with the GPU and Dask to manage parallelism.
I'll build a custom Docker container that includes the libraries we need, as well as other useful tools.
I'll then deploy this container to a DeepOps cluster using [Kubernetes](https://kubernetes.io/), and show how to run the benchmark and experiment further.

The steps outlined below were tested using a virtual DeepOps cluster that included one dedicated management node, as well as two compute nodes that were each allocated 8 CPU cores, 16 GB memory, and a single NVIDIA Tesla P4 GPU.
Any cluster hardware should work to duplicate this example, provided that each compute node you use for the benchmark includes at least one CUDA-capable GPU.

## Assumptions

These instructions assume that:

* You have already set up a [Kubernetes cluster using DeepOps](/docs/kubernetes-cluster.md).
* Your cluster has a [MetalLB load balancer](/docs/ingress.md) configured for ingress.
* You have privileges to run containers in your cluster.
* All compute nodes in your cluster have at least one CUDA-capable GPU.
* You have push access to a container registry, whether local or public.
    * DeepOps is capable of running a local container registry, but the configuration for the registry  is out of scope for this example. The example below uses the public [Docker Hub](https://hub.docker.com) registry.

## Deploying a custom RAPIDS container

### A note on registries

This example will include building a custom container image that includes the libraries we need for integrating RAPIDS, Dask, and Kubernetes.
Because we're building a custom image, we need to push the image to some container registry that Kubernetes can pull from to run the job.
DeepOps includes support for running a local registry, but configuration of that system can be site-specific and is out of scope for this example.

In my workflow below, I am pushing the image to [Docker Hub](https://hub.docker.com).
If you haven't used Docker Hub before, the [quickstart documentation](https://docs.docker.com/docker-hub/) provides a good tutorial.

### Editing the deployment scripts

We'll deploy the RAPIDS/Dask container in one step using the `deploy.sh` script.
This script builds the image, pushes it to the registry, and deploys the container using Helm.
To make sure we're pointing to the right registry, we'll need to edit this script and the deployment definition.

1. In `deploy.sh`, replace the tag in the `docker build` command with a tag identifying your image in the registry.
    In this case, I'm pushing to the Docker Hub repository `ajdecon/dask-rapids-example`.
    So the change to the script looks like this:
    ```
    @@ -30,7 +30,7 @@ function build_image() {
       pushd tmp-rapids-build
    
       # Build the docker image
    -  docker build -t dask-rapids
    +  docker build -t ajdecon/deepops-example-k8s-dask-rapids .
    
       popd
       rm -rf tmp-rapids-build
    ```
1. In the same script, replace the `TODO` comment for pushing the image with your `docker push` command.
    ```
    @@ -36,7 +36,7 @@ function build_image() {
       rm -rf tmp-rapids-build
    
    
    -  # TODO: Push the docker  image
    +  docker push ajdecon/deepops-example-k8s-dask-rapids
    
     }
    ```
1. We also need to edit the Helm config for the RAPIDS deployment to point to the correct image.
    Edit the `helm/rapids-dask.yml` file to point to the right image:
    ```
    --- a/examples/k8s/dask-rapids/helm/rapids-dask.yml
    +++ b/examples/k8s/dask-rapids/helm/rapids-dask.yml
    @@ -5,7 +5,7 @@
     worker:
       image:
         # repository: nvcr.io/nvidia/rapidsai/rapidsai
    -    repository: dask-rapids
    +    repository: ajdecon/deepops-example-k8s-dask-rapids
         tag: latest
         env:
       replicas: 3
    @@ -17,14 +17,14 @@ worker:
    
     scheduler:
       image:
    -    repository: dask-rapids
    +    repository: ajdecon/deepops-example-k8s-dask-rapids
         tag: latest
    
     # By default we should be doing all Dask works on workers using calls to distributed.Client()
     # If you would like to run/test your GPU code without using workers you may comment the resources section
     jupyter:
       image:
    -    repository: dask-rapids
    +    repository: ajdecon/deepops-example-k8s-dask-rapids
         tag: latest
       resources:
         requests:
    ```

### Running the deployment

At this point we can run the deployment:

```
ubuntu@ivb120:~/src/deepops/examples/k8s/dask-rapids$ ./deploy.sh
....... (lots of Docker and Kubernetes output follows) ........
```

The image build can take some time, so this is a good chance to get up and make a cup of coffee. ;-)
When the script is completed, you should be able to run the following commands to get URLs for Jupyter and Dask:

```
export DASK_SCHEDULER=$(kubectl get svc --namespace rapids rapids-dask-scheduler -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

export DASK_SCHEDULER_UI_IP=$(kubectl get svc --namespace rapids rapids-dask-scheduler -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

export JUPYTER_NOTEBOOK_IP=$(kubectl get svc --namespace rapids rapids-dask-jupyter -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo http://$JUPYTER_NOTEBOOK_IP:80 -- Jupyter notebook

echo http://$DASK_SCHEDULER_UI_IP:80  -- Dask dashboard

echo http://$DASK_SCHEDULER:8786    -- Dask Client connection
```

If you open your browser and go to the URL for Jupyter, you can log in with the default password `dask`.
You'll then find yourself in JupyterLab session where you can interact with the RAPIDS and Dask libraries.
If you open a terminal window (File -> New -> Terminal in the JupyterLab menu), you should even be able to run `nvidia-smi` to see your GPUs:

![Screenshot of running nvidia-smi in JupyterLab](/examples/k8s/dask-rapids/jupyterlab-nvsmi.png "Screenshot of running nvidia-smi in JupyterLab")

## Running the benchmark

Once you have JupyterLab open, load the `ParallelSum.ipynb` notebook using the file pane.
This notebook will step through running a simple parallel sum benchmark on both the CPUs and GPUs in your cluster.
Feel free to adjust the number of CPU cores or GPUs used and the parameters for the model to experiment with the calculation.

![Screenshot of the parallel sum notebook](/examples/k8s/dask-rapids/parallel-sum.png "Screenshot of the parallel sum notebook")

## Experimenting further

The base container we used for this benchmark contains more examples using RAPIDS in the `cuml/` directory,
as well as an end-to-end workflow example based on a Fannie Mae mortgage dataset in the `mortgage/` directory.
Both directories can be accessed easily via JupyterLab.

You can also experiment with the custom container by making changes to the `Dockerfile` used to create it,
in `examples/k8s/dask-rapids/docker`.

For more information on RAPIDS, check out [https://rapids.ai](https://rapids.ai).
