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

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. 

   ```sh
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

3. Create the server inventory. 

   Ansible uses an inventory which outlines the servers in your cluster. Use the script below to create the server inventory by supplying host IP addresses as argument inputs. 

   ```sh
   # Specify IP addresses of Kubernetes nodes
   ./scripts/k8s_inventory.sh 10.0.0.1 10.0.0.2 10.0.0.3
   ``` 

   A `k8s-config` inventory directory should now exist. Optionally, modify the `k8s-config/hosts.ini` to configure hosts for specific roles (ex: master node vs worker node). 

   ```sh
   # (optional) Modify `k8s-config/hosts.ini` to configure hosts for specific roles
   # 	     Make sure the [etcd] group has an odd number of hosts
   ```

4. Install Kubernetes using Ansible. 

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -i k8s-config/hosts.ini -b playbooks/k8s-cluster.yml
   ```

5. Verify that the Kubernetes cluster is running. 

   ```sh
   # You may need to manually run: `sudo cp ./k8s-config/artifacts/kubectl /usr/local/bin`
   kubectl get nodes
   ``` 

   Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs. 

   ```sh
   kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
   ```

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

### Monitoring

Deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes:

```sh
./scripts/k8s_deploy_monitoring.sh
```

### Container Registry

The default container registry hostname is `registry.local`. To set another hostname (for example,
one that is resolvable outside the cluster), add `-e container_registry_hostname=registry.example.com`.

```sh
ansible-playbook -i k8s-config/hosts.ini -b --tags container-registry playbooks/k8s-services.yml
```

### Kubeflow

Kubeflow is a popular way for multiple users to run ML workloads. It exposes a Jupyter Notebook interface where users can request access to GPUs via the browser GUI. Deploy Kubeflow with a convenient script:

```sh
./scripts/k8s_deploy_kubeflow.sh
```

For more on Kubeflow, please refer to the [official documentation](https://www.kubeflow.org/docs/about/kubeflow/).

## Using Kubernetes

Now that Kubernetes is installed, consult the [Kubernetes Usage Guide](kubernetes-usage.md) for examples of how to use Kubernetes.

## Additional Documentation

[Ansible](ANSIBLE.md)

More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

