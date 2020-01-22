#!/bin/bash
set -ex

# Get absolute path for script, and convenience vars for virtual and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VIRT_DIR="${SCRIPT_DIR}/.."
ROOT_DIR="${SCRIPT_DIR}/../.."

#####################################
# Configure slurm in virtual cluster 
#####################################

# Move working directory to root of DeepOps repo
cd "${ROOT_DIR}" || exit 1

DEEPOPS_OFFLINE="${DEEPOPS_OFFLINE:-0}"
ansible_extra_args=""
if [ "${DEEPOPS_OFFLINE}" -ne 0 ]; then
	ansible_extra_args="-e "@${VIRT_DIR}/config/offline_repo_vars.yml" --skip-tags configure_docker_repo -vv"
fi

# Configure Slurm cluster
ansible-playbook \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-cluster \
	-e "@${VIRT_DIR}/vars_files/virt_slurm.yml" ${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/slurm-cluster.yml"

# Configure NFS server for /shared
ansible-playbook \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-master \
	-e "@${VIRT_DIR}/vars_files/virt_slurm.yml" ${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/nfs-server.yml"

# Configure NFS clients for /shared
ansible-playbook \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-node \
	-e "@${VIRT_DIR}/vars_files/virt_slurm.yml" ${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/nfs-client.yml"
