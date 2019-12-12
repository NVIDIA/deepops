Kubernetes Deployment Guide
===

Instructions for deploying a GPU cluster with Kubernetes

## Requirements

  * Control system to run the install process
  * One or more servers on which to install Kubernetes

## Installation Steps

1. Install a supported operating system on all nodes. 

   Install a supported operating system on all servers via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)) or utilize the provided [OS install container](PXE.md).

2. Set up your provisioning machine. 

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md). 

   ```sh
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create and edit the Ansible inventory. 

   Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the `config` directory. 
   
   Edit the inventory: 
   
   ```sh
   # Edit inventory and add nodes to the "KUBERNETES" section
   # Note: Etcd requires an odd number of servers
   vi config/inventory
   
   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
   ```
4. Verify the configuration

   ```sh
   ansible all -m raw -a "hostname"
   ```

5. Install Kubernetes using Ansible and Kubespray.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml
   ```
   
   More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

6. Verify that the Kubernetes cluster is running.

   ```sh
   # You may need to manually run: `sudo cp ./config/artifacts/kubectl /usr/local/bin`
   kubectl get nodes
   ``` 

   Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs. 

   ```sh
   kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
   ```

## Using Kubernetes

Now that Kubernetes is installed, consult the [Kubernetes Usage Guide](kubernetes-usage.md) for examples of how to use Kubernetes.

## Optional Components

The following components are completely optional and can be installed on an existing Kubernetes cluster.

### Kubernetes Dashboard

Run the following script to create an administrative user and print out the dashboard URL and access token:

```sh
./scripts/k8s_deploy_dashboard_user.sh
```

### Persistent Storage

Deploy a Ceph cluster running on Kubernetes for services that require persistent storage (such as Kubeflow):

```sh
./scripts/k8s_deploy_rook.sh
```

Poll the Ceph status by running:

```sh
./scripts/ceph_poll.sh
```

### Monitoring

Deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes:

```sh
./scripts/k8s_deploy_monitoring.sh
```

The services can be reached from the following addresses:
* Grafana: http://mgmt:30200
* Prometheus: http://mgmt:30500
* Alertmanager: http://mgmt:30400

### Logging

Follow the [ELK Guide](elk.md) to setup logging in the cluster.

The service can be reached from the following address:
* Kibana: http://mgmt:30700

### Container Registry

The default container registry hostname is `registry.local`. To set another hostname (for example,
one that is resolvable outside the cluster), add `-e container_registry_hostname=registry.example.com`.

```sh
ansible-playbook --tags container-registry playbooks/k8s-services.yml
```

### Load Balancer and Ingress

Many K8s applications require the deployment of a Load Balancer and Ingress. To deploy one, or both, of these services, refer to the [Load Balancer and Ingress Guide](ingress.md).

### Kubeflow

Kubeflow is a popular way for multiple users to run ML workloads. It exposes a Jupyter Notebook interface where users can request access to GPUs via the browser GUI. Deploy Kubeflow with a convenient script:

```sh
./scripts/k8s_deploy_kubeflow.sh
```

For more on Kubeflow, please refer to the [official documentation](https://www.kubeflow.org/docs/about/kubeflow/).

## Cluster Maintenance

DeepOps uses [Kubespray](https://github.com/kubernetes-sigs/kubespray) to deploy Kubernetes and therefore common cluster actions (such as adding nodes, removing them, draining and upgrading the cluster) should be performed with it. Kubespray is included as a submodule in the deepops/kubespray directory.

### Adding Nodes

To add K8s nodes, modify the `config/inventory` file to include the new nodes under `[all]`. Then list the nodes as relevant under the `[kube-master]`, `[etcd]`, and `[kube-node]` sections. For example, if adding a new master node, list it under kube-master and etcd. A new worker node would go under kube-node.

Then run the Kubespray `scale.yml` playbook...

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook -l k8s-cluster kubespray/scale.yml
```

More information on this topic may be found in the [Kubespray docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#adding-nodes).

### Removing Nodes

Removing nodes can be performed with Kubespray's `remove-node.yml` playbook and supplying the node names as extra vars...

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook kubespray/remove-node.yml --extra-vars "node=nodename0,nodename1"
```

This will drain `nodename0` & `nodename1`, stop Kubernetes services, delete certificates, and finally execute the kubectl command to delete the nodes.

More information on this topic may be found in the [Kubespray docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#remove-nodes).

### Reset the Cluster

Sometimes a cluster will get into a bad state - perhaps one where certs are misconfigured or different across nodes. When this occurs it's often helpful to completely reset the cluster. To accomplish this, run the `remove-node.yml` playbook for all k8s nodes...

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
ansible-playbook kubespray/remove-node.yml --extra-vars "node=k8s-cluster"
```

> NOTE: There is also a Kubespray `reset.yml` playbook, but this does not do a complete tear-down of the cluster.

### Upgrading the Cluster

Refer to the [Kubespray Upgrade docs](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/upgrades.md) for instructions on how to upgrade the cluster.
