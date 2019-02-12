NVIO
===

*"NVIDIA Infrastructure Ops"*

Universal GPU Server Software Stack

## Components:

  * [Operating System Installation](#operating-system-installation)
  * [Operating System Configuration](#operating-system-configuration)
  * [Orchestration Layer Installation](#orchestration-layer-installation)

**See the [Getting Started Guide](docs/GETTINGSTARTED.md) for step-by-step instructions and more
detailed setup information.**

## Operating System Installation

Install a supported operating system (Ubuntu/RHEL) on GPU servers via
a 3rd-party solution or utilize the provided OS install container

### OS Install via 3rd-party solutions:

  * [MAAS](https://maas.io/)
  * [Foreman](https://www.theforeman.org/)

### OS Install Container

#### Working with an existing DHCP server

Modify `pxe/docker-compose.yml`

Start the PXE server:

```sh
docker-compose -f pxe/docker-compose.yml up -d pxe-ubuntu
```

#### Working with no existing DHCP server

Modify `pxe/docker-compose.yml`

Modify `pxe/dhcp/dnsmasq.conf`

Start the DHCP and PXE servers:

```sh
docker-compose -f pxe/docker-compose.yml up -d dhcp pxe-ubuntu
```

For more information on PXE installation, see the [docs](docs/PXE.md)

## Operating System Configuration

Server configuration is done via Ansible. Go here for detailed instructions: [docs/ANSIBLE.md](docs/ANSIBLE.md)

### Requirements

  * Control machine with supported OS to run Ansible
  * [Passwordless](docs/ANSIBLE.md#passwordless-configuration-using-ssh-keys) (SSH key) access from Ansible system to Universal GPU servers

### Installation and Usage

_Install Ansible_

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh

# Install required Ansible roles
ansible-galaxy install -r requirements.yml
```

_Create server inventory_

```sh
# Copy the default configuration and edit
cp configuration.yml.example configuration.yml
vi configuration.yml
```

_Configure GPU Servers_

```sh
# If sudo requires a password, add the -K flag
ansible-playbook playbooks/setup-gpu-servers.yml
```

## Orchestration Layer Installation

### Kubernetes

Kubernetes is installed via the Kubespray project, which uses Ansible

#### Requirements

  * Control machine with Ansible installed and configured: [docs/ANSIBLE.md](docs/ANSIBLE.md)
  * Systems configured per [Operating System Configuration](#operating-system-configuration) section

#### Installation

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

For more information on Kubespray, see the [docs](docs/KUBESPRAY.md)

#### Accessing Kubernetes

```sh
# Obtain the Kubernetes admin user config file
./scripts/setup_remote_k8s.sh

# Test access is working
kubectl get nodes
```

### Slurm
