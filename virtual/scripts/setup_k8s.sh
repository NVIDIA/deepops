#!/bin/bash
set -ex

# Get absolute path for script, and convenience vars for virtual and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VIRT_DIR="${SCRIPT_DIR}/.."
ROOT_DIR="${SCRIPT_DIR}/../.."

#####################################
# Configure k8s in virtual cluster 
#####################################

# Move working directory to root of DeepOps repo
cd "${ROOT_DIR}" || exit 1

# Create the K8s config (for mgmt=10.0.0.2, gpu01=10.0.0.11 nodes)
K8S_CONFIG_DIR="${VIRT_DIR}/k8s-config" "${ROOT_DIR}/scripts/k8s_inventory.sh" 10.0.0.2 10.0.0.11
cp "${VIRT_DIR}/k8s_hosts.ini" "${VIRT_DIR}/k8s-config/hosts.ini"

# Deploy the K8s cluster
ansible-playbook -i "${VIRT_DIR}/k8s-config/hosts.ini" -b "${ROOT_DIR}/playbooks/k8s-cluster.yml"

# Source K8s environment for interacting with the cluster
# shellcheck disable=SC1091 disable=SC1090
source "${VIRT_DIR}/k8s_environment.sh"

# Verify that the cluster is up
kubectl get nodes
#kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Install helm
./scripts/install_helm.sh

# Deploy MetalLB load balancer (optional but recommended)
helm install --name metallb --values "${VIRT_DIR}/config/helm/metallb.yml" stable/metallb

# Deploy dashboard (optional)
./scripts/k8s_deploy_dashboard_user.sh

# Deploy rook (optional, but highly recommended)
./scripts/k8s_deploy_rook.sh

# Deploy monitoring (optional)
./scripts/k8s_deploy_monitoring.sh
