#!/bin/bash
set -ex

# Start vagrant via libvirt - set up the VMs
vagrant up --no-parallel --provider=libvirt

# Show the running VMs
virsh list

cd ..

# Create the K8s config (for mgmt=10.0.0.2, gpu01=10.0.0.11 nodes)
K8S_CONFIG_DIR=./virtual/k8s-config ./scripts/k8s_inventory.sh 10.0.0.2 10.0.0.11
cp ./virtual/k8s_hosts.ini ./virtual/k8s-config/hosts.ini

# Create the config for deepops servers (and use the virtual inventory)
export DEEPOPS_CONFIG_DIR="$(pwd)/virtual/config"
cp -r config.example/ ${DEEPOPS_CONFIG_DIR}/
cp virtual/virtual_inventory ${DEEPOPS_CONFIG_DIR}/inventory

#####################################
# K8s
#####################################

# Deploy the K8s cluster
ansible-playbook -i virtual/k8s-config/hosts.ini -b playbooks/k8s-cluster.yml -e "ansible_user=vagrant ansible_password=vagrant"

# Export k8s config so we can use it throughout the rest of the script
export KUBECONFIG=virtual/k8s-config/artifacts/admin.conf

# Put local kubectl in the PATH for following commands and scripts
export PATH="$(pwd)/virtual/k8s-config/artifacts:${PATH}"

# Verify that the cluster is up
kubectl get nodes
#kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Deploy dashboard (optional)
#./scripts/k8s_deploy_dashboard_user.sh

# Deploy rook (optional, but highly recommended)
#./scripts/k8s_deploy_rook.sh

# Deploy monitoring (optional)
#./scripts/k8s_deploy_monitoring.sh

# Deploy container registry (optional)
#ansible-playbook -i virtual/k8s-config/hosts.ini -b --tags container-registry playbooks/k8s-services.yml -e "ansible_user=vagrant ansible_password=vagrant"

#####################################
# Slurm
#####################################

# Deploy the Slurm cluster
#ansible-playbook -i virtual/config/inventory -e "ansible_user=vagrant ansible_password=vagrant" -l slurm-cluster playbooks/slurm-cluster.yml
