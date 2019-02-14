Kubernetes Cluster Build
===

Minimal step-by-step instructions for deploying a Kubernetes GPU cluster

**Requirements**

  * Control system to run the install process
  * One or more servers with a supported operating system installed (Ubuntu/RHEL) on which to install Kubernetes 
  * [Passwordless](ANSIBLE.md#passwordless-configuration-using-ssh-keys) (SSH key) access from control machine to cluster nodes

**Installation**

```sh
# Install Ansible (installation script for Ubuntu/RHEL)
./scripts/install_ansible.sh

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
ansible-playbook playbooks/k8s-cluser.yml

# Access the Kubernetes cluster by obtaining the admin user config file
./scripts/setup_remote_k8s.sh

# Test access is working
kubectl get nodes
```
