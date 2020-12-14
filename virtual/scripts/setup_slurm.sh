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

# Use ansible install in virtualenv
# NOTE: Added here because this script is also called from Jenkinsfile and not just cluster_up.sh
if [ -d env ] ; then
    . env/bin/activate
else
    echo "WARNING: virtual env not detected, using system python install"
fi

# Configure Slurm cluster
ansible-playbook \
	-i "${VIRT_DIR}/config/inventory" \
	-l slurm-cluster \
	-e "@${VIRT_DIR}/vars_files/virt_slurm.yml" \
	"${ROOT_DIR}/playbooks/slurm-cluster.yml"
