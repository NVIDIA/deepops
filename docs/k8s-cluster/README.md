# Kubernetes Deployment Guide

Instructions for deploying a GPU cluster with Kubernetes

- [Kubernetes Deployment Guide](#kubernetes-deployment-guide)
  - [Requirements](#requirements)
  - [Installation Steps](#installation-steps)
  - [Using Kubernetes](#using-kubernetes)
  - [Optional Components](#optional-components)
    - [Kubernetes Dashboard](#kubernetes-dashboard)
    - [Persistent Storage](#persistent-storage)
      - [NFS Client Provisioner](#nfs-client-provisioner)
      - [Ceph Cluster (deprecated)](#ceph-cluster-deprecated)
      - [NetApp Astra Trident](#netapp-astra-trident)
    - [Monitoring](#monitoring)
    - [Logging](#logging)
      - [Centralized syslog](#centralized-syslog)
      - [ELK logging](#elk-logging)
    - [Container Registry](#container-registry)
    - [Load Balancer and Ingress](#load-balancer-and-ingress)
    - [Kubeflow](#kubeflow)
    - [NVIDIA Network Operator](#nvidia-network-operator)
  - [Cluster Maintenance](#cluster-maintenance)
    - [Adding Nodes](#adding-nodes)
    - [Removing Nodes](#removing-nodes)
    - [Reset the Cluster](#reset-the-cluster)
    - [Upgrading the Cluster](#upgrading-the-cluster)

## Requirements

- Control system to run the install process
- One or more servers on which to install Kubernetes

## Installation Steps

1. Install a supported operating system on all nodes.

   Install a supported operating system on all servers via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided [OS install container](../pxe).

2. Set up your provisioning machine.

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](../deepops/ansible.md).

   ```bash
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create and edit the Ansible inventory.

   Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the `config` directory.

   Edit the inventory:

   ```bash
   # Edit inventory and add nodes to the "KUBERNETES" section
   # Note: Etcd requires an odd number of servers
   vi config/inventory

   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
   ```

   Note that as part of the kubernetes deployment process, the default behavior is to also deploy the [NVIDIA k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) for GPU support. The [GPU Operator](https://github.com/NVIDIA/gpu-operator) is an alternative all-in-one deployment method, which will deploy the [device plugin](https://github.com/NVIDIA/k8s-device-plugin) and optionally includes GPU tooling such as driver containers, [GPU Feature Discovery](https://github.com/NVIDIA/gpu-feature-discovery), [DCGM-Exporter](https://github.com/NVIDIA/dcgm-exporter) and [MIG Manager](https://github.com/NVIDIA/mig-parted). The default behavior of the [GPU Operator](https://github.com/NVIDIA/gpu-operator) in DeepOps is to deploy host-level drivers and NVIDIA software. To leverage driver containers as part of the GPU Operator, disable the `gpu_operator_preinstalled_nvidia_software` flag. To enable the GPU Operator in DeepOps...

   ```bash
   vi config/group_vars/k8s-cluster.yml

   # Enable GPU Operator
   # set: deepops_gpu_operator_enabled: true

   # Enable host-level drivers (must be 'true' for clusters with pre-installed NVIDIA drivers or DGX systems)
   # set: gpu_operator_preinstalled_nvidia_software: true
   ```

4. Verify the configuration

   ```bash
   ansible all -m raw -a "hostname"
   ```

5. Install Kubernetes using Ansible and Kubespray.

   ```bash
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml
   ```

   More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

6. Verify that the Kubernetes cluster is running.

   ```bash
   # You may need to manually run: `sudo cp ./config/artifacts/kubectl /usr/local/bin`
   kubectl get nodes
   ```

   Optionally, verify all GPU nodes plug-ins in the Kubernetes cluster with following script.

   ```bash
   export CLUSTER_VERIFY_EXPECTED_PODS=1 # Expected number of GPUs in the cluster
   ./scripts/k8s/verify_gpu.sh
   ```

## Using Kubernetes

Now that Kubernetes is installed, consult the [Kubernetes Usage Guide](kubernetes-usage.md) for examples of how to use Kubernetes or see the [example workloads](../../workloads/examples/k8s/README.md).

## Optional Components

The following components are completely optional and can be installed on an existing Kubernetes cluster.

### Kubernetes Dashboard

Run the following script to create an administrative user and print out the dashboard URL and access token:

```bash
./scripts/k8s/deploy_dashboard_user.sh
```

### Persistent Storage

#### NFS Client Provisioner

The default behavior of DeepOps is to setup an NFS server on the first `kube-master` node. This temporary NFS server is used by the `nfs-client-provisioner` which is installed as the default StorageClass of a standard DeepOps deployment.

To use an existing nfs server server update the `k8s_nfs_server` and `k8s_nfs_export_path` variables in `config/group_vars/k8s-cluster.yml` and set the `k8s_deploy_nfs_server` to false in `config/group_vars/k8s-cluster.yml`. Additionally, the `k8s_nfs_mkdir` variable can be set to `false` if the export directory is already configured on the server.

To manually install or re-install the `nfs-client-provisioner` run:

```bash
ansible-playbook playbooks/k8s-cluster/nfs-client-provisioner.yml
```

To skip this installation set `k8s_nfs_client_provisioner` to `false`.

#### Ceph Cluster (deprecated)

For a non-nfs based alternative, deploy a Ceph cluster running on Kubernetes for services that require persistent storage (such as Kubeflow):

```bash
./scripts/k8s/deploy_rook.sh
```

Poll the Ceph status by running (this script will return when Ceph initialization is complete):

```bash
./scripts/k8s/deploy_rook.sh -w
```

#### NetApp Astra Trident

Deploy NetApp Astra Trident for services that require persistent storage (such as Kubeflow). Note that you must have a supported NetApp storage system/instance/service in order to use Astra Trident to provision persistent storage.

1. Set configuration parameters.

   ```bash
   vi config/group_vars/netapp-trident.yml
   ```

2. Deploy Astra Trident using Ansible.

   ```bash
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l k8s-cluster playbooks/k8s-cluster/netapp-trident.yml
   ```

3. Verify that Astra Trident is running.

   ```bash
   ./tridentctl -n deepops-trident version
   ```

   Output of the above command should resemble the following:

   ```console
   +----------------+----------------+
   | SERVER VERSION | CLIENT VERSION |
   +----------------+----------------+
   | 22.01.0        | 22.01.0        |
   +----------------+----------------+
   ```

For more information on Astra Trident, please refer to the [official documentation](https://docs.netapp.com/us-en/trident/index.html).

### Monitoring

Deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes:

```bash
./scripts/k8s/deploy_monitoring.sh
```

Available Flags:

```bash
-h      This message.
-p      Print monitoring URLs.
-d      Delete monitoring namespace and crds. Note, this may delete PVs storing prometheus metrics.
-x      Disable persistent data, this deploys Prometheus with no PV backing resulting in a loss of data across reboots.
-w      Wait and poll the grafana/prometheus/alertmanager URLs until they properly return.
delete  Legacy positional argument for delete. Same as -d flag.
```

The services can be reached from the following addresses:

- Grafana: http://\<kube-master\>:30200
- Prometheus: http://\<kube-master\>:30500
- Alertmanager: http://\<kube-master\>:30400

We deploy our monitoring services using the [prometheus-operator](https://github.com/prometheus-operator/prometheus-operator) project.
For documentation on configuring and managing the monitoring services, please see the [prometheus-operator user guides](https://github.com/prometheus-operator/prometheus-operator/tree/master/Documentation/user-guides).
The source for our built-in Grafana dashboards can be found in [src/dashboards](../../src/dashboards).

### Logging

#### Centralized syslog

To enable syslog forwarding from the cluster nodes to the first Kubernetes controller node, you can set the following variables in your DeepOps configuration:

```bash
kube_enable_rsyslog_server: true
kube_enable_rsyslog_client: true
```

For more information about our syslog forwarding functionality, please see the [centralized syslog guide](../misc/syslog.md).

#### ELK logging

Follow the [ELK logging Guide](logging.md) to setup logging in the cluster.

The service can be reached from the following address:

- Kibana: http://\<kube-master\>:30700

### Container Registry

The default container registry hostname is `registry.local`. To set another hostname (for example, one that is resolvable outside the cluster), add `-e container_registry_hostname=registry.example.com`.

```bash
ansible-playbook --tags container-registry playbooks/k8s-cluster/container-registry.yml
```

### Load Balancer and Ingress

Many K8s applications require the deployment of a Load Balancer and Ingress. To deploy one, or both, of these services, refer to the [Load Balancer and Ingress Guide](ingress.md).

### Kubeflow

Kubeflow is a popular way for multiple users to run ML workloads. It exposes a Jupyter Notebook interface where users can request access to GPUs via the browser GUI and allows a user to build automated AI pipelines. To deploy Kubeflow refer to the [DeepOps Kubeflow Guide](kubeflow.md).

For more information on Kubeflow, please refer to the [official documentation](https://www.kubeflow.org/docs/about/kubeflow/).

### NVIDIA Network Operator

NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage networking related components in Kuberenets cluster. High performance networking in Kuberentes requires many components, such as multus-CNI, device drivers and plugins to be installed correctly, NVIDIA network operator aims to manage all those necessary components automatically under one operator frame work to simply the deployment, operation and management of NVIDIA networking for Kubernetes. To deploy NVIDIA network operator, please refer to the [NVIDIA Network Operator Deployment Guide in DeepOps](nvidia-network-operator.md), for more information on NVIDIA network operator, please refer to its [github](https://github.com/Mellanox/network-operator) page and this [solution guide](https://docs.nvidia.com/networking/display/COKAN10/Network+Operator).

## Cluster Maintenance

DeepOps uses [Kubespray](https://github.com/kubernetes-sigs/kubespray) to deploy Kubernetes and therefore common cluster actions (such as adding nodes, removing them, draining and upgrading the cluster) should be performed with it. Kubespray is included as a submodule in the submodules/kubespray directory.

### Adding Nodes

To add K8s nodes, modify the `config/inventory` file to include the new nodes under `[all]`. Then list the nodes as relevant under the `[kube-master]`, `[etcd]`, and `[kube-node]` sections. For example, if adding a new master node, list it under kube-master and etcd. A new worker node would go under kube-node.

Then run the Kubespray `scale.yml` playbook...

```bash
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l k8s-cluster submodules/kubespray/scale.yml
```

More information on this topic may be found in the [Kubespray docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#adding-nodes).

### Removing Nodes

Removing nodes can be performed with Kubespray's `remove-node.yml` playbook and supplying the node names as extra vars...

```bash
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook submodules/kubespray/remove-node.yml --extra-vars "node=nodename0,nodename1"
```

This will drain `nodename0` & `nodename1`, stop Kubernetes services, delete certificates, and finally execute the kubectl command to delete the nodes.

More information on this topic may be found in the [Kubespray docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#remove-nodes).

### Reset the Cluster

DeepOps is largely idempotent, but in some cases, it is helpful to completely reset a cluster. KubeSpray provides a best-effort attempt at this through a playbook. The script below is recommended to be run twice as some components may not completely uninstall due to time-outs/failed dependent conditions.

```bash
ansible-playbook submodules/kubespray/reset.yml
```

### Upgrading the Cluster

Refer to the [Kubespray Upgrade docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/upgrades.md) for instructions on how to upgrade the cluster.
