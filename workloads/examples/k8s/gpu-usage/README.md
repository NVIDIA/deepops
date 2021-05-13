# Example GPU YAML configurations

This directory contains several yaml files that act as examples of how to consume GPUs within Kubernetes.

When working in smaller homogeneous clusters that only have one GPU type or MIG configuration, the simpler examples work well. However, clusters with multiple GPU types or different MIG configurations require the use of both `NodeSelectors` and `Resource Limits` as shown.

## Using NodeSelectors

Using a `NodeSelector` guarentees that a Pod will only deploy with a GPU that meets the requested criteria. This can include a specific GPU type by specifying the `nvidia.com/gpu.product` label, the GPU architecture by specifying the `nvidia.com/gpu.family`, or the available GPU memory by specifying the `nvidia.com/gpu.memory` label.

When using `mig-strategy=single` or deploying into a cluster with multiple GPU types, specifying a `NodeSelector` is mandatory for consistent results.

For more information on selecting nodes, see the Kubernetes documenaiton on [Node Selectors](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector) and [Node Affinity](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/).

For more information on the labels available, see the [GPU Feature Discovery repo](https://github.com/NVIDIA/gpu-feature-discovery).

Request a V100 running in a DGX:
```sh
nodeSelector:
  nvidia.com/gpu.product: Tesla-V100-DGXS-32GB
```

Request any NVIDIA Ampere card:
```sh
nodeSelector:
  nvidia.com/gpu.family: ampere
```

Request any NVIDIA Ampere card with more than 16GB of memory:
```sh
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: nvidia.com/gpu.family
          operator: In
          values:
          - ampere
        - key: nvidia.com/gpu.memory
          operator: Gt
          values:
          - 16384
```

## Using Resource Limits

Requesing a resource limit is how the Pod tells Kubernetes it needs a GPU. This is required and the Pod will always get exactly how many GPUs are requested.

It is not possible to request a partial GPU or share a GPU without using MIG on the NVIDIA Ampere and newer GPUs.

If MIG is not being used, a GPU is requests by specifying `nvidia.com/gpu` in the resource limits. This stays the same if MIG is being used with `mig-strategy=single`, but must be combined with a `NodeSelector`. If MIG is being used with `mig-strategy=mixed`, then a MIG device is requesting by using one of the `nvidia.com/mig-<compute>g-<memory>gb` profiles listed below.

For more information on the MIG strategies, see the [GPU Device Plugin documentation](https://github.com/NVIDIA/k8s-device-plugin#deployment-via-helm).


```sh
resources:
  limits:
    nvidia.com/gpu: 1
```

Available resource types:
```sh
# Full GPU or MIG device when in mig-strategy=single
nvidia.com/gpu

# MIG profiles available on the NVIDIA A100 40GB
nvidia.com/mig-1g.5gb
nvidia.com/mig-2g.10gb
nvidia.com/mig-4g.20gb
nvidia.com/mig-7g.40gb

# MIG profiles available on the NVIDIA A100 80GB
nvidia.com/mig-1g.10gb
nvidia.com/mig-2g.20gb
nvidia.com/mig-4g.40gb
nvidia.com/mig-7g.80gb
```
