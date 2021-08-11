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

ansible_extra_args=""

# Extra vars file
if [ ${DEEPOPS_LARGE_SLURM} ]; then
  SLURM_EXTRA_VARS="${SLURM_EXTRA_VARS:-${VIRT_DIR}/vars_files/virt_large_slurm.yml}"
else
  SLURM_EXTRA_VARS="${SLURM_EXTRA_VARS:-${VIRT_DIR}/vars_files/virt_slurm.yml}"
fi

# Use ansible install in virtualenv
# NOTE: Added here because this script is also called from Jenkinsfile and not just cluster_up.sh
if [ -d env ] ; then
    . env/bin/activate
else
    echo "WARNING: virtual env not detected, using system python install"
fi

# Configure Slurm cluster
ansible-playbook -vv \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-cluster \
	--forks 16 \
	-e "@${SLURM_EXTRA_VARS}" ${ansible_extra_args} \
	"${ROOT_DIR}/playbooks/slurm-cluster.yml"

# Un-drain nodes
ansible-playbook \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-cluster \
	-e "@${VIRT_DIR}/vars_files/virt_slurm.yml" ${ansible_extra_args} \
	--tags undrain \
	"${ROOT_DIR}/playbooks/slurm-cluster/slurm.yml"
