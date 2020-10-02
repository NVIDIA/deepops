# Supporting Multi-Instance GPUs (MIG) in Kubernetes

Multi-Instance GPU or MIG is a feature introduced in the NVIDIA A100 GPUs that allow a single GPU to be partitioned into several smaller GPUs. For more information see the [NVIDIA MIG page](https://www.nvidia.com/en-us/technologies/multi-instance-gpu/).

Supporting MIG requires several administrative steps and open source projects.

*Projects:*
* [GPU Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
* [GPU Feature Discovery](https://github.com/NVIDIA/gpu-feature-discovery)

*Admin Steps:*
* Enable MIG
* Configure MIG (kubernetes)
* Configure MIG (bare-metal)
* Update Application/YAML to support MIG


## Enabling MIG

MIG can be enabled on a node by running the `playbooks/nvidia-software/nvidia-mig.yml` playbook.

There are some caveats depending on the state of your cluster and a node reboot may be necessary.


## Installing MIG in Kubernetes

By default, MIG support for Kubernetes is enabled in DeepOps. The default MIG strategy used is set to `mixed`. This can be controlled by the `k8s_gpu_mig_strategy`variable in `config/group_vars/k8s-cluster.yml. The "mixed" strategy is recommended for new deployments. For more information about strategies see the GPU Device Plugin [README](https://github.com/NVIDIA/k8s-device-plugin#deployment-via-helm).

If DeepOps is being used to manage a Kubernetes cluster that was deployed using another method, MIG can be enabled by running:

```sh
ansible-playbook playbooks/k8s-cluster/nvidia-k8s-gpu-device-plugin.yml playbooks/k8s-cluster/nvidia-k8s-gpu-feature-discovery.yml
```
> Note, the same command can be used to re-configure a new strategy

## Configuring MIG

MIG devices must be configured after enabling MIG and after **every** node reboot. When in production, it is recommended to do a rolling upgrade node-by-node following the below steps on each GPU node.

Configuration and reconfiguration require that you:

1. Taint your node
2. Evacuate all GPU pods
3. Configure MIG
4. Restart the GPU Device Plugin Pod
5. Wait for GPU Feature Discovery to re-label the node
6. Remove the taint.

```sh
kubectl taint node gpu01 mig=maintenance:NoSchedule
kubectl taint node gpu01 mig=maintenance:NoExecute # Optionally, Deep Learning jobs and Notebooks could be allowed to "time out"

<Manual configuration steps>

kubectl exec <GPU Device Plugin Pod on gpu01> -- kill -SIGTERM 1
sleep 60 # 60 seconds is the default polling period of GPU Feature Discovery
kubectl taint node gpu01 mig=maintenance:NoSchedule-
kubectl taint node gpu01 mig=maintenance:NoExecute-
```

For information on configuring MIG see the [official documentation](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/).


## Using MIG in Kubernetes

See "Requesting MIG devices with each Strategy" in [the K8S MIG guide](https://docs.google.com/document/u/1/d/1mdgMQ8g7WmaI_XVVRrCvHPFPOMCm5LQD5JefgAh6N8g) for full details.

Example YAML:

```sh
# Request a MIG using nodeSelector
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  nodeSelector:
    nvidia.com/gpu.product: A100-SXM4-40GB-MIG-1g.5g
  containers:
    - name: cuda-nbody-container
      image: nvcr.io/nvidia/k8s/cuda-sample:nbody
      resources:
        limits:
          nvidia.com/gpu: 1
```
> Single Strategy, note the nodeSelector

```sh
# Request MIG using resource limit
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  containers:
    - name: cuda-nbody-container
      image: nvcr.io/nvidia/k8s/cuda-sample:nbody
      resources:
        limits:
          nvidia.com/mig-1g.5gb: 1
```
> Mixed Strategy, note the resource limit


## Misc.

For additional installation and configuration information, see the official guide on [supporting Multi-Instance GPUs in Kubernetes](https://docs.google.com/document/u/1/d/1mdgMQ8g7WmaI_XVVRrCvHPFPOMCm5LQD5JefgAh6N8g).
