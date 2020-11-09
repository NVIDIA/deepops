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

# Set the K8s Ansible config directory (same as for Slurm)
K8S_CONFIG_DIR="${VIRT_DIR}/config"

DEEPOPS_OFFLINE="${DEEPOPS_OFFLINE:-0}"
ansible_extra_args=""
if [ "${DEEPOPS_OFFLINE}" -ne 0 ]; then
	ansible_extra_args="-e "@${VIRT_DIR}/config/airgap/offline_repo_vars.yml""
fi

# Deploy the K8s cluster
ansible-playbook \
	-b -i "${VIRT_DIR}/config/inventory" \
	-e "@${VIRT_DIR}/vars_files/virt_k8s.yml" \
	${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/k8s-cluster.yml"

# Source K8s environment for interacting with the cluster
# shellcheck disable=SC1091 disable=SC1090
source "${VIRT_DIR}/k8s_environment.sh"

# Verify that the cluster is up
file ${K8S_CONFIG_DIR}/artifacts/kubectl && chmod +x ${K8S_CONFIG_DIR}/artifacts/kubectl
kubectl get nodes
#kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Install helm
"${ROOT_DIR}/scripts/k8s/install_helm.sh"

# Deploy dashboard (optional)
"${ROOT_DIR}/scripts/k8s/deploy_dashboard_user.sh"

# Deploy rook (optional, but highly recommended)
"${ROOT_DIR}/scripts/k8s/deploy_rook.sh"

# Deploy load balancer and ingress (optional but recommended)
"${ROOT_DIR}/scripts/k8s/deploy_loadbalancer.sh"
"${ROOT_DIR}/scripts/k8s/deploy_ingress.sh"

# Deploy monitoring (optional)
"${ROOT_DIR}/scripts/k8s/deploy_monitoring.sh"

# Deploy container registry (optional)
ansible-playbook \
	-b -i "${VIRT_DIR}/config/inventory" \
	-e "@${VIRT_DIR}/vars_files/virt_k8s.yml" \
	${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/k8s-cluster/container-registry.yml"
