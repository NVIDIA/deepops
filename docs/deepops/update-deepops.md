# Update DeepOps

Updating a cluster deployed with DeepOps

- [Update DeepOps](#update-deepops)
  - [Updating the DeepOps repository](#updating-the-deepops-repository)
    - [A note on DeepOps updates](#a-note-on-deepops-updates)
    - [Updating the repository](#updating-the-repository)
    - [Porting your configuration](#porting-your-configuration)
  - [Updating Kubernetes clusters](#updating-kubernetes-clusters)
    - [Overview](#overview)
    - [Re-deploying the full cluster](#re-deploying-the-full-cluster)
    - [Component-based upgrades](#component-based-upgrades)
      - [Updating Kubernetes](#updating-kubernetes)
        - [Troubleshooting: failure to drain node when Kubeflow is installed](#troubleshooting-failure-to-drain-node-when-kubeflow-is-installed)
      - [Update verification](#update-verification)
      - [Updating the NVIDIA GPU Operator](#updating-the-nvidia-gpu-operator)
      - [Updating NVIDIA Kubernetes components (no GPU Operator)](#updating-nvidia-kubernetes-components-no-gpu-operator)
        - [Overview](#overview-1)
        - [Updating the NVIDIA driver](#updating-the-nvidia-driver)
          - [On DGX](#on-dgx)
          - [On Ubuntu](#on-ubuntu)
          - [On RHEL](#on-rhel)
        - [Updating the NVIDIA Container Runtime](#updating-the-nvidia-container-runtime)
        - [Updating NVIDIA GPU Feature Discovery](#updating-nvidia-gpu-feature-discovery)
        - [Updating the NVIDIA GPU Device Plugin](#updating-the-nvidia-gpu-device-plugin)
    - [Updating the monitoring stack](#updating-the-monitoring-stack)
      - [Minor version upgrades](#minor-version-upgrades)
      - [Major version upgrades](#major-version-upgrades)
    - [Updating OS packages](#updating-os-packages)
      - [On Ubuntu](#on-ubuntu-1)
      - [On RHEL](#on-rhel-1)
  - [Updating Slurm clusters](#updating-slurm-clusters)
    - [Overview](#overview-2)
    - [Component-based upgrades](#component-based-upgrades-1)
      - [Updating Slurm](#updating-slurm)
      - [Updating the NVIDIA driver](#updating-the-nvidia-driver-1)
        - [On DGX](#on-dgx-1)
        - [On Ubuntu](#on-ubuntu-2)
        - [On RHEL](#on-rhel-2)
      - [Updating the CUDA toolkit](#updating-the-cuda-toolkit)
      - [Updating the monitoring stack (excluding dcgm-exporter)](#updating-the-monitoring-stack-excluding-dcgm-exporter)
      - [Updating dcgm-exporter](#updating-dcgm-exporter)
      - [Updating Enroot and Pyxis](#updating-enroot-and-pyxis)
    - [Installing a new HPC SDK](#installing-a-new-hpc-sdk)
    - [Updating OS packages](#updating-os-packages-1)
      - [On Ubuntu](#on-ubuntu-3)
      - [On RHEL](#on-rhel-3)

## Updating the DeepOps repository

### A note on DeepOps updates

DeepOps should be considered a deployment toolkit, rather than an integrated bundle of released software. Each new release of DeepOps brings new features in terms of software that can be deployed, or the configuration options supported by the Ansible playbooks.

However, updating to a new DeepOps release doesn’t necessarily require updating the software components you have deployed to a cluster, and in most cases, you don’t need to update the DeepOps repository to install new software versions on your cluster.

When updating a cluster deployed with DeepOps, we generally recommend updating individual components based on the particular features or bugfixes you want to track, rather than performing blanket updates. For example, you may want to upgrade the NVIDIA driver on a different schedule than Kubernetes.

Most of the component-based upgrades detailed below do not require updating the DeepOps repository itself.

### Updating the repository

Each release of DeepOps is a named tag of the Git repository, with versions using the YY.MM numbering scheme. So, for example, the March 2019 release of DeepOps is a tag named 19.03.

If you don’t have a local clone of the DeepOps repository, you should clone one to your local provisioning host.

```bash
git clone https://github.com/NVIDIA/deepops
```

Check out the git tag for the release you’re upgrading to:

```bash
git checkout <YY.MM>
```

If you want to create a new branch to retain commits you create, you may do so (now or later) by using -b with the checkout command again. Example:

```bash
git checkout -b <new-branch-name>
```

If you’ve made local changes to the DeepOps repository in your own branch, you can rebase your branch onto the release to port your changes to the new release.

```bash
git checkout <your-branch>
git rebase <YY.MM>
```

Note that if there are any conflicts between your local branch and the release, you will need to resolve those conflicts as part of the rebase process.

### Porting your configuration

The DeepOps configuration files sometimes change from one release to the next. You should compare your existing configuration (usually in the config/ directory) to the example configuration provided by DeepOps (in config.example/) to identify new required parameters or changes in the config structure.

To identify any configuration changes between releases you may run:

```bash
git diff 21.06 21.09 -- config.example/
```

## Updating Kubernetes clusters

### Overview

This section assumes you are performing a disruptive upgrade to the cluster. This means that we expect you are not running any production workloads on the cluster, and should expect pods or even nodes to be restarted at will.

If you plan to perform a more graceful upgrade, we recommend that you upgrade each node individually, [safely draining it before the upgrade](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) and then uncordoning it after.

Performing these component-based upgrades does not require updating the DeepOps repository to a new release.

### Re-deploying the full cluster

**Warning:** re-deploying the cluster will remove any persistent volumes stored on the cluster.
By default, persistent volumes are stored on the first Kubernetes management node under `/export/deepops_nfs` as defined by the Ansible variables `k8s_nfs_server` and `k8s_nfs_export_path`, and exported using the NFS client provisioner. As a result of running the below `reset.yml`, all PVs stored in this directory will be moved to `/export_deepops_nfs/archived_<pv_uuuid>`; however it is advised that you manually ensure your critical data is backed up on external storage before trying this procedure.

In some instances, you may want to start fresh with a newly-deployed Kubernetes cluster, rather than upgrading existing components.

Before resetting the cluster, ensure you have a DeepOps repo checked out at the same version tag of your initial deployment. For example, if the cluster was originally deployed using DeepOps 21.03, ensure you have checked out the 21.03 tag during the reset process.

First, reset the cluster using the Kubespray reset playbook:

```bash
ansible-playbook submodules/kubespray/reset.yml
```

Ensure this playbook has completed cleanly before continuing.

Once the cluster has been reset, edit your DeepOps configuration to specify your desired software versions, or remove any pinned versions that you want to allow to be upgraded. If you want to update the DeepOps repository to a different version tag, do that as well.

Then re-run the DeepOps k8s-cluster playbook:

```bash
ansible-playbook playbooks/k8s-cluster.yml
```

And re-deploy any desired workloads.

### Component-based upgrades

#### Updating Kubernetes

For updating Kubernetes itself to a new revision, we recommend following the upgrade instructions provided by Kubespray for the particular version of DeepOps in use.
For example, DeepOps 21.09 uses Kubespray v2.16.0, with upgrade instructions found [here](https://github.com/kubernetes-sigs/kubespray/blob/release-2.16/docs/upgrades.md).

When performing an update, it's important to make sure that your configured versions align with the supported versions in the version of Kubespray you are using.
In particular,

- Make sure the `helm_version` variable in your `config/group_vars/k8s-cluster.yml` file matches the version supported in the current Kubespray release.
  You can determine this version by running:

  ```bash
  grep -E "^helm_version:" submodules/kubespray/roles/download/defaults/main.yml
  helm_version: "v3.5.4"
  ```

- Make sure the `kube_version` you are using appears in the list of supported versions in `kubectl_checksums`.
  You can verify your supported version appears in the list by checking the `kubectl_checksums` variable in the `submodules/kubespray/roles/download/defaults/main.yml` file.

Additionally, please note that Kubespray can only upgrade between one minor version of Kubernetes at a time.
This means that you may need to upgrade multiple times between your current version and your desired version of Kubernetes.

For example, to upgrade from Kubernetes version 1.19.9 and 1.21.1, you might use a workflow like this:

```bash
# Starting at version v1.19.9
ansible-playbook -e kube_version=v1.20.7 submodules/kubespray/upgrade-cluster.yml
ansible-playbook -e kube_version=v1.21.1 submodules/kubespray/upgrade-cluster.yml
```

Where each version of Kubernetes in the chain should be supported by the Kubespray release in use.

##### Troubleshooting: failure to drain node when Kubeflow is installed

If Kubeflow has been installed on your Kubernetes cluster, you may find that the upgrade process fails due to an inability to drain nodes where Istio pods are running.
The default configuration for Istio sets a [pod disruption budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) which may prevent these pods from being migrated.

In this case, you can work around the issue by disabling the Istio pod disruption budgets and restoring them following the upgrade.

1. Show the pod disruption budget configuration for the Istio namespace
   ```bash
   kubectl -n istio-system get pdb
   NAME                     MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
   cluster-local-gateway    1               N/A               1                     3m40s
   istio-galley             1               N/A               0                     3m40s
   istio-ingressgateway     1               N/A               0                     3m40s
   istio-pilot              1               N/A               0                     3m40s
   istio-policy             1               N/A               1                     3m40s
   istio-sidecar-injector   1               N/A               1                     3m40s
   istio-telemetry          1               N/A               0                     3m40s
   ```
1. Save the pod disruption configuration to a file
   ```bash
   kubectl -n istio-system get pdb -o yaml > config/istio-pdb.yaml
   ```
1. Remove the pod disruption budget objects from the active cluster
   ```bash
   $ for x in $(kubectl -n istio-system get pdb  | grep -v NAME | awk '{print $1}'); do echo ${x}; kubectl -n istio-system delete pdb ${x}; done
   cluster-local-gateway
   poddisruptionbudget.policy "cluster-local-gateway" deleted
   istio-galley
   poddisruptionbudget.policy "istio-galley" deleted
   istio-ingressgateway
   poddisruptionbudget.policy "istio-ingressgateway" deleted
   istio-pilot
   poddisruptionbudget.policy "istio-pilot" deleted
   istio-policy
   poddisruptionbudget.policy "istio-policy" deleted
   istio-sidecar-injector
   poddisruptionbudget.policy "istio-sidecar-injector" deleted
   istio-telemetry
   poddisruptionbudget.policy "istio-telemetry" deleted
   ```
1. Proceed with your Kubernetes upgrade
1. Once the upgrade is complete, restore the pod disruption budget configuration
   ```bash
   kubectl apply -f config/istio-pdb.yaml
   poddisruptionbudget.policy/cluster-local-gateway created
   poddisruptionbudget.policy/istio-galley created
   poddisruptionbudget.policy/istio-ingressgateway created
   poddisruptionbudget.policy/istio-pilot created
   poddisruptionbudget.policy/istio-policy created
   poddisruptionbudget.policy/istio-sidecar-injector created
   poddisruptionbudget.policy/istio-telemetry created
   ```

#### Update verification

All of the NVIDIA-specific K8s components and most of the DeepOps included services rely on Helm for installation and upgrade. These installation packages include built-in validation steps as part of the install. To verify that a component has been installed and upgraded correctly there are two commands you can run. Note that any NVIDIA-provided pods or Helm applications will have a name such as `nvidia-<service>-<uuid>`.

Verify the Helm install is in a Ready or Completed state by running:

```bash
helm list -aA
```

Verify the Pods are all in a Ready or Completed state by running:

```bash
kubectl get pods -aA
```

#### Updating the NVIDIA GPU Operator

The [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) automates the process of setting up all necessary components for a Kubernetes cluster to make use of NVIDIA GPUs. The GPU Operator is used in a DeepOps cluster when `deepops_gpu_operator_enabled` is set to true. In general, the below steps can be applied to upgrade the GPU Operator helm charts, but for certain major releases their may be additional upgrade steps, please refer to the GPU Operator release notes before performing this upgrade.

To update to a new version of the GPU operator, set the following parameter in your DeepOps configuration:

```bash
gpu_operator_chart_version: "1.8.2"
```

Substituting in your desired version.

Then re-run the GPU operator playbook:

```bash
ansible-playbook playbooks/k8s-cluster/nvidia-gpu-operator.yml
```

#### Updating NVIDIA Kubernetes components (no GPU Operator)

##### Overview

DeepOps offers the option to configure each of the necessary NVIDIA components individually on the cluster, rather than using the GPU Operator. This option is used when `deepops_gpu_operator_enabled` is set to false. This is likely the configuration you used if setting up a cluster with NVIDIA DGX systems.

##### Updating the NVIDIA driver

**Important**: Note that upgrading the NVIDIA driver will reboot the node, unless you set `nvidia_driver_skip_reboot` to false.
If you are using MIG-enabled GPUs ensure that your MIG configuration is persistent by using the [nvidia-mig-manager systemd](https://github.com/NVIDIA/mig-parted/tree/master/deployments/systemd) service
or the [nvidia-mig-manager Kubernetes GPU Operator-included DaemonSet](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/gpu-operator-mig.html).

###### On DGX

To update the driver on a DGX system, we recommend following the instructions in the DGX User Guide.

###### On Ubuntu

On Ubuntu, the default behavior in DeepOps is to use the LTS release branch distributed through the Ubuntu repositories. In this mode, the driver is generally pinned to a particular release branch such as 450 or 470.

To upgrade to the latest driver within your current release branch, run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml -e nvidia_driver_package_state="latest" [-l <list-of-nodes>]
```

To upgrade the driver to a new release branch, set the following parameter in your DeepOps configuration:

```bash
nvidia_driver_ubuntu_branch: "470"
```

Then run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml [-l <list-of-nodes>]
```

###### On RHEL

On RHEL and related distros, DeepOps uses the driver distributed in the CUDA repository. To upgrade to the latest driver, run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml -e nvidia_driver_package_state="latest" [-l <list-of-nodes>]
```

##### Updating the NVIDIA Container Runtime

To update the NVIDIA container runtime to the latest release, run the following command on each node:

```bash
sudo apt-get install nvidia-container-runtime
```

##### Updating NVIDIA GPU Feature Discovery

Updating GFD should typically be non-disruptive, and does not need to be run on a per-node basis.

To update to a new version of GFD, set the following variable in your DeepOps configuration:

```bash
k8s_gpu_feature_discovery_chart_version: "0.4.1"
```

substituting your desired version of the feature discovery chart.

Then run:

```bash
ansible-playbook playbooks/k8s-cluster/nvidia-k8s-gpu-feature-discovery.yml
```

##### Updating the NVIDIA GPU Device Plugin

Updating the GPU Device Plugin should typically be non-disruptive, and does not need to be run on a per-node basis.

To update to a new version, set the following variable in your DeepOps configuration:

```bash
k8s_gpu_plugin_chart_version: "0.9.0"
```

substituting your desired version of the device plugin chart.

Then run:

```bash
ansible-playbook playbooks/k8s-cluster/nvidia-k8s-gpu-device-plugin.yml
```

### Updating the monitoring stack

We deploy our monitoring stack using the [kube-prometheus-stack project](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

Metrics data is stored using a Kubernetes persistent volume with PVC named `monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0`.
By default, this data is stored on the first Kubernetes management node and exported using NFS from `/export/deepops_nfs`. Before upgrading the monitoring stack, we recommend backing this data up.

To check which version of this stack was deployed by default using your deployment script, run:

```bash
helm list -n monitoring
NAME                    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                           APP VERSION
kube-prometheus-stack   monitoring      1               2021-10-14 15:27:58.663573206 +0000 UTC deployed        kube-prometheus-stack-10.0.2    0.42.1
```

Here, the deployed version of kube-prometheus-stack is 10.0.2.

The procedure for updating the stack will be different depending on whether it is a minor version update of the kube-prometheus-stack (e.g., 10.0.2 to 10.3.4) or a major update (e.g., 10.x to 11.x).

#### Minor version upgrades

To perform a minor version upgrade, run:

```bash
helm upgrade -n monitoring kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 10.3.4
```

Substituting your desired version number.

#### Major version upgrades

For major version upgrades, see the instructions documented in the [README for the kube-prometheus-stack project](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md).

### Updating OS packages

#### On Ubuntu

To update the underlying OS packages on the nodes, run the following on each node:

```bash
sudo apt-get update
sudo apt-get full-upgrade
```

#### On RHEL

To update the underlying OS packages on the nodes, run the following on each node:

```bash
sudo yum update
```

## Updating Slurm clusters

### Overview

This section assumes you are performing a disruptive upgrade to the cluster. This means that we expect you are not running any production workloads on the cluster, and should expect nodes to be restarted at will.

If you plan to perform a more graceful upgrade, we recommend that you upgrade each node individually, draining it and then resuming it in Slurm.

Performing these component-based upgrades does not require updating the DeepOps repository to a new release.

### Component-based upgrades

#### Updating Slurm

**Important:** Slurm generally supports upgrading within two major releases without loss of state information or accounting data. E.g., you can upgrade to 21.08 from 20.11 or 20.02, but not prior releases. We recommend consulting the release notes for your desired version of Slurm before running an upgrade.

To upgrade to a new version of Slurm, modify your DeepOps configuration to specify your desired Slurm version:

```bash
slurm_version: 21.08.0
```

Then re-run the Slurm playbook:

```bash
ansible-playbook playbooks/slurm-cluster/slurm.yml [-l <list-of-nodes>]
```

Note that this can take a long time, as we download and build Slurm from source in this process.

#### Updating the NVIDIA driver

**Important**: Note that upgrading the NVIDIA driver will reboot the node, unless you set `nvidia_driver_skip_reboot` to false.

##### On DGX

To update the driver on a DGX system, we recommend following the instructions in the DGX User Guide.

##### On Ubuntu

On Ubuntu, the default behavior in DeepOps is to use the LTS release branch distributed through the Ubuntu repositories. In this mode, the driver is generally pinned to a particular release branch such as 450 or 470.

To upgrade to the latest driver within your current release branch, run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml -e nvidia_driver_package_state="latest" [-l <list-of-nodes>]
```

To upgrade the driver to a new release branch, set the following parameter in your DeepOps configuration:

```bash
nvidia_driver_ubuntu_branch: "510"
```

Then run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml [-l <list-of-nodes>]
```

##### On RHEL

On RHEL and related distros, DeepOps uses the driver distributed in the CUDA repository. To upgrade to the latest driver, run:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-driver.yml -e nvidia_driver_package_state="latest" [-l <list-of-nodes>]
```

#### Updating the CUDA toolkit

To upgrade to a new version of the CUDA toolkit, edit your DeepOps configuration and specify the name of the new toolkit package you wish to install. For example,

```bash
cuda_version: "cuda-toolkit-11-3"
```

Then re-run the CUDA toolkit playbook:

```bash
ansible-playbook playbooks/nvidia-software/nvidia-cuda.yml
```

#### Updating the monitoring stack (excluding dcgm-exporter)

The monitoring stack on a Slurm cluster deployed with DeepOps is container-based. For most of these, we use the "latest" tag by default. So in order to upgrade, all you typically need to do is run "docker pull" for the container in question and then restart the service.

On the monitoring host, the commands to use are:

```bash
docker pull prom/prometheus
systemctl restart docker.prometheus
docker pull grafana/grafana
systemctl restart docker.grafana
docker pull deepops/prometheus-slurm-exporter
systemctl restart docker.slurm-exporter
```

On the compute nodes, the commands to use are:

```bash
docker pull quay.io/prometheus/node-exporter
systemctl restart docker.node-exporter
```

#### Updating dcgm-exporter

For the NVIDIA DCGM Exporter, we do pin a particular version of the container. To update to a newer version, edit your DeepOps configuration to specify a new container tag:

```
nvidia_dcgm_container_version: "2.1.8-2.4.0-rc.2-ubuntu20.04"
```

Then re-run the playbook:

```bash
ansible-playbook -l slurm-node playbooks/slurm-cluster/nvidia-dcgm-exporter.yml
```

#### Updating Enroot and Pyxis

To update Pyxis and/or Enroot, edit your DeepOps configuration and specify the new versions you wise to use:

```bash
slurm_pyxis_version: "0.11.1"
enroot_version: "3.2.0"
```

Then re-run the Pyxis playbook:

```bash
ansible-playbook playbooks/container/pyxis.yml [-l <list-of-nodes>]
```

### Installing a new HPC SDK

The NVIDIA HPC SDK is installed in versioned directories, so that new versions are installed alongside the old ones.

To install a newer HPC SDK, first configure the version variables in your DeepOps configuration:

```bash
hpcsdk_major_version: "21"
hpcsdk_minor_version: "9"
hpcsdk_file_cuda: "11.4"
hpcsdk_arch: "x86_64"
```

Then re-run the playbook to install:

```bash
ansible-playbook -l <install-node> playbooks/nvidia-software/nvidia-hpc-sdk.yml
```

Note that we typically install the HPC SDK in an NFS-shared directory, so this playbook only has to be executed on one node. The cluster login node is typically used.

### Updating OS packages

#### On Ubuntu

To update the underlying OS packages on the nodes, run the following on each node:

```bash
sudo apt-get update
sudo apt-get full-upgrade
```

#### On RHEL

To update the underlying OS packages on the nodes, run the following on each node:

```bash
sudo yum update
```
