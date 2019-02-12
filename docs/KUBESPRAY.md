Kubespray
===

More information on Kubespray can be found in the official [Getting Started Guide](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)

## Requirements

  * Control machine with Ansible installed and configured: [docs/ANSIBLE.md](docs/ANSIBLE.md)
  * Systems configured per [Operating System Configuration](#operating-system-configuration) section

## Installation

```sh
# Make sure kubespray is up to date
git submodule update --init

# Copy the kubespray default configuration
cp -rfp kubespray/inventory/sample/ k8s-config

# Update Ansible inventory file and configuration with inventory builder
declare -a IPS=(10.0.0.1 10.0.0.2 10.0.0.3)
CONFIG_FILE=k8s-config/hosts.ini python3 kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}

# Modify `k8s-config/hosts.ini` to configure hosts for specific roles
# Make sure the [etcd] group has an odd number of hosts

# Install Kubernetes
ansible-playbook -b kubespray/cluster.yml
```

## Accessing Kubernetes

```sh
# Obtain the Kubernetes admin user config file
./scripts/setup_remote_k8s.sh

# Test access is working
kubectl get nodes
```
