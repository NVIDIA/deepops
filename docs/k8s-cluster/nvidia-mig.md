# NVIDIA MIG

Supporting Multi-Instance GPUs (MIG) in Kubernetes

- [NVIDIA MIG](#nvidia-mig)
  - [Enabling MIG](#enabling-mig)
  - [Configuring MIG Mode in Kubernetes](#configuring-mig-mode-in-kubernetes)
  - [Configuring MIG Devices](#configuring-mig-devices)
  - [Using MIG in Kubernetes](#using-mig-in-kubernetes)
  - [Misc.](#misc)

Multi-Instance GPU or MIG is a feature introduced in the NVIDIA A100 GPUs that allow a single GPU to be partitioned into several smaller GPUs. For more information see the [NVIDIA MIG page](https://www.nvidia.com/en-us/technologies/multi-instance-gpu/).

There are two methods that can be used to administer MIG. This guide details the K8s native method that relies on the NVIDIA MIG Manager service included with the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) and installed by default if `deepops_gpu_operator_enabled` is set to `true`. The alternative method is a bare-metal solution using the mig-parted systemd service which can be installed using the [nvidia-mig.yml](../../playbooks/nvidia-software/nvidia-mig.yml) playbook and configured following the [official documentation](https://github.com/NVIDIA/mig-parted).

Supporting MIG requires several administrative steps and open source projects.

_Projects, included in GPU Operator v1.9.0+:_

- [GPU Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [GPU Feature Discovery](https://github.com/NVIDIA/gpu-feature-discovery)
- [NVIDIA K8s MIG Manager](https://github.com/NVIDIA/mig-parted/tree/master/deployments/gpu-operator)

_Admin Steps:_

- Enable MIG
- Configure MIG mode ('single' or 'mixed')
- Configure MIG (Kubernetes configmap)
- Update Application/YAML to support MIG

## Enabling MIG

The K8s MIG Manager will handle enabling and disabling MIG on all devices, as necessary.

There are some caveats depending on the state of your cluster and a node reboot may be necessary.

## Configuring MIG Mode in Kubernetes

By default, MIG support for Kubernetes is enabled in DeepOps. The default MIG strategy used is set to `mixed`. This can be controlled by the `k8s_gpu_mig_strategy`variable in `config/group_vars/k8s-cluster.yml. The "mixed" strategy is recommended for new deployments. For more information about strategies see the GPU Device Plugin [README](https://github.com/NVIDIA/k8s-device-plugin#deployment-via-helm).

If DeepOps is being used to manage a Kubernetes cluster that was deployed using another method, MIG can be enabled by running:

```bash
ansible-playbook playbooks/k8s-cluster/nvidia-gpu-operator.yml
```

> Note, the same command can be used to re-configure a new strategy

## Configuring MIG Devices

MIG devices are configured on a per-node or cluster-wide basis depending on the MIG configmap and the node labels applied to each node. When in production, it is recommended to do a rolling upgrade node-by-node following the below steps on each GPU node.

Configuration and reconfiguration require that you:

1. Taint your node
2. Evacuate all GPU pods
3. Configure MIG
4. Remove the taint

```bash
kubectl taint node gpu01 mig=maintenance:NoSchedule
kubectl taint node gpu01 mig=maintenance:NoExecute # Optionally, Deep Learning jobs and Notebooks could be allowed to "time out"
kubectl label node gpu01 nvidia.com/mig.config=all-1g.5gb
sleep 60 # 60 seconds is the default polling period of GPU Feature Discovery
kubectl describe node gpu01 # Manual verification of MIG resources
kubectl taint node gpu01 mig=maintenance:NoSchedule-
kubectl taint node gpu01 mig=maintenance:NoExecute-
```

For information on configuring MIG see the [official documentation](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/).

## Using MIG in Kubernetes

See "Requesting MIG devices with each Strategy" in [the K8S MIG guide](https://docs.google.com/document/u/1/d/1mdgMQ8g7WmaI_XVVRrCvHPFPOMCm5LQD5JefgAh6N8g) for full details.

Example YAML:

```yaml
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

```yaml
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
