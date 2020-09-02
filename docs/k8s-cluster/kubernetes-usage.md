Kubernetes Usage Guide
===

## Introduction

Most of the following examples can be configured and executed through the Kubernetes Dashboard. For a basic run-through on how to leverage the Kubernetes Dashboard, please see the [official documentation](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). The following examples `kubectl` on the master node instead.

## Simple Commands

Get a list of the nodes in the cluster:

```sh
kubectl get nodes
```

Get a list of running pods in the cluster:

```sh
kubectl get pods --all-namespaces
```

## Simple PyTorch Job

1. Run the job. 

   A simple PyTorch Job can be run via `kubectl` using the following yml: 

   ```sh
   kubectl create -f tests/pytorch-job.yml
   ``` 

   Take a look at the yml and observe that:

   * we are pulling a pytorch container from the NGC registry
   * a single GPU resource is requested
   * the Kubernetes object we are creating is a `job` which spawns `pod` and runs this pod to completion a single time

2. Check on the job. 

   ```sh
   kubectl get jobs
   ```
   
3. Monitor the pod that's spawned from the job.

   ```sh
   kubectl get pods
   ```
   
   Follow the logs for the pod:
   
   ```sh
   kubectl logs -f <pytorch-job-pod>
   ```
   
4. Delete the job (and the corresponding pod). 

   ```sh
   kubectl delete job cuda-job
   ```

## Using NGC Containers with Kubernetes and Launching Jobs

[NVIDIA GPU Cloud (NGC)](https://docs.nvidia.com/ngc/ngc-introduction) manages a catalog of fully integrated and optimized DL framework containers that take full advantage of NVIDIA GPUs in both single and multi-GPU configurations. They include NVIDIA CUDA® Toolkit, DIGITS workflow, and the following DL frameworks: NVCaffe, Caffe2, Microsoft Cognitive Toolkit (CNTK), MXNet, PyTorch, TensorFlow, Theano, and Torch. These framework containers are delivered ready-to-run, including all necessary dependencies such as the CUDA runtime and NVIDIA libraries.

To access the NGC container registry via Kubernetes, add a secret which will be employed when Kubernetes asks NGC to pull container images from it.

1. Generate an NGC API Key, which will be used for the Kubernetes secret. 
   * Login to the NGC Registry at https://ngc.nvidia.com/
   * Go to https://ngc.nvidia.com/configuration/api-key
   * Click on GENERATE API KEY

2. Using the NGC API Key, create a Kubernetes secret so that Kubernetes will be able to pull container images from the NGC registry. Create the secret by running the following command on the master (substitute the registered email account and secret in the appropriate locations).

   ```sh
   kubectl create secret docker-registry nvcr.dgxkey --docker-server=nvcr.io --docker-username=\$oauthtoken --docker-email=<email> --docker-password=<NGC API Key>
   ```

3. Check that the secret exists.

   ```sh
   kubectl get secrets
   ```
   
4. You can now use the secret to pull custom NGC images by using the `imagePullSecrets` attribute. For example:

   ```yml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: pytorch-job
   spec:
     backoffLimit: 5
     template:
       spec:
         imagePullSecrets:
           - name: nvcr.dgxkey
         containers:
           - name: pytorch-container
             image: nvcr.io/nvidia/pytorch:19.02-py3
             command: ["/bin/sh"]
             args: ["-c", "python /workspace/examples/upstream/mnist/main.py"]
             resources:
               limits:
                 nvidia.com/gpu: 1
         restartPolicy: Never
   ```
