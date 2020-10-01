# Kubeflow

[Kubeflow](https://www.kubeflow.org/docs/) is a K8S native tool that eases the Deep Learning and Machine Learning lifecycle.

Kubeflow allows users to request specific resources (such as number of GPUs and CPUs), specify Docker images, and easily launch and develop through Jupyter models. Kubeflow makes it easy to create persistent home directories, mount data volumes, and share notebooks within a team.

Kubeflow also offers a full deep learning [pipeline](https://www.kubeflow.org/docs/pipelines/overview/pipelines-overview/) platform that allows you to run, track, and version experiments. Pipelines can be used to deploy code to production and can include all steps in the training process (data prep, training, tuning, etc.) each done through different Docker images. For some examples reference the [examples](../examples) directory.

Additionally Kubeflow offers [hyper-parameter tuning](https://github.com/kubeflow/katib) options.

Kubeflow is an [open source project](https://github.com/kubeflow/kubeflow) and is regularly evolving and adding [new features](https://github.com/kubeflow/kubeflow/blob/master/ROADMAP.md).

As part of the Kubeflow installation, the MPI Operator will also be installed. This will add the `MPIJob` CustomResourceDefinition to the cluster, enabling multi-pod or multi-node workloads. See [here](https://github.com/kubeflow/mpi-operator/tree/master/) for details and examples.

## Installation

Deploy Kubernetes by following the [DeepOps Kubernetes Deployment Guide](README.md)

Deploy [Ceph](kubernetes-cluster.md#persistent-storage). Kubeflow requires a DefaultStorageClass to be defined, either deploy Ceph or use an alternative StorageClass.

Deploy Kubeflow:

```sh
# Deploy (using istio configuration)
./scripts/k8s/deploy_kubeflow.sh

```

Deploy Kubeflow with Dex and SSO integration:

```sh
# Deploy (using istio_dex configuration)
./scripts/k8s/deploy_kubeflow.sh -x

```

See the [install docs](https://www.kubeflow.org/docs/started/k8s/overview/) for additional install configuration options.

Kubeflow configuration files will be saved to `./config/kubeflow-install`.

The kfctl binary will be saved to `./config/kfctl`. For easier management this file can be copied to `/usr/local/bin` or added to the `PATH`.

The services can be reached from the following address:
* Kubeflow: http://\<kube-master\>:31380

## Login information

The default username is `admin@kubeflow.org` and the default password is `12341234`.

These can be modified at startup time following the steps outlined [here](https://www.kubeflow.org/docs/started/k8s/kfctl-existing-arrikto/).

## Other usage

For the most up-to-date usage information run `./scripts/k8s/deploy_kubeflow.sh -h`.

```sh
./scripts/k8s/deploy_kubeflow.sh -h
Usage:
-h    This message.
-p    Print out the connection info for Kubeflow.
-d    Delete Kubeflow from your system (skipping the CRDs and istio-system namespace that may have been installed with Kubeflow.
-D    Deprecated, same as -d. Previously 'Fully Delete Kubeflow from your system along with all Kubeflow CRDs the istio-system namespace. WARNING, do not use this option if other components depend on istio.'
-x    Install Kubeflow with multi-user auth (this utilizes Dex, the default is no multi-user auth).
-c    Specify a different Kubeflow config to install with (this option is deprecated).
-w    Wait for Kubeflow homepage to respond (also polls for various Kubeflow Deployments to have an available status).
```

## Kubeflow Admin

### Uninstalling

To uninstall and re-install Kubeflow run:

```sh
./scripts/k8s/deploy_kubeflow.sh -d
./scripts/k8s/deploy_kubeflow.sh
```

### Modifying Kubeflow configuration

To modify the Kubeflow configuration, modify the downloaded `CONFIG` YAML file in `config/kubeflow-install/` or one of the many overlay YAML files in `config/kubeflow-install/kustomize`.

After modifying the configuration, apply the changes to the cluster using `kfctl`:

```sh
cd config/kubeflow-install
../kfctl apply -f kfctl_k8s_istio.yaml
```

## Debugging common issues

### No DefaultStorageClass defined or ready

A common issue with Kubeflow installation is that no DefaultStorageClass has been defined or that Ceph has been not been deployed correctly.

This can be idenfitied if most of the Kubeflow Pods are running and the MySQL pod and several others remain in a Pending state. The GUI may also load and throw a "Profile Error". Run the following to debug further:

```sh
kubectl get pods -n kubeflow
```
> NOTE: Everything should be in a running state.

Verify Ceph is running and/or a DefaultStorageClass is defined:

```
kubectl get storageclass | grep default
./scripts/k8s/poll_ceph.sh
```
> NOTE: If Ceph is being used, `poll_ceph.sh` should exit after several seconds and Ceph should be the default StorageClass. 


To correct this issue:
1. Uninstall Rook/Ceph: `./scripts/k8s/delete_rook.sh`
2. Uninstall Kubeflow: `./scripts/k8s/deploy_kubeflow.sh -D`
3. Re-install Rook/ceph: `./scripts/k8s/deploy_rook.sh`
4. Poll for Ceph to initialize (wait for this script to exit): `./scripts/k8s/poll_ceph.sh`
5. Re-install Kubeflow: `./scripts/k8s/deploy_kubeflow.sh`
