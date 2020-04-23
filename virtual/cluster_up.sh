#!/bin/bash
set -ex

#####################################
# Set up a virtual DeepOps cluster
#####################################

# Get absolute path for the virtual DeepOps directory
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${VIRT_DIR}/.."

# Ensure working directory is root
cd "${ROOT_DIR}"

# Ensure Ansible Galaxy dependencies are present
bash -x ./scripts/setup.sh

# Use ansible install in virtualenv
if [ -d env ] ; then
    . env/bin/activate
else
    echo "WARNING: virtual env not detected, using system python install"
fi

export DEEPOPS_CONFIG_DIR="${VIRT_DIR}/config"

# Ensure clean config dirs for a new turnup
DEEPOPS_VIRT_CLEAN_CONFIG="${DEEPOPS_VIRT_CLEAN_CONFIG:-1}"
if [ "${DEEPOPS_VIRT_CLEAN_CONFIG}" -ne 0 ]; then
	rm -rf "${VIRT_DIR}/config"
	cp -r "${ROOT_DIR}/config.example/" "${DEEPOPS_CONFIG_DIR}/"
	cp "${VIRT_DIR}/virtual_inventory" "${DEEPOPS_CONFIG_DIR}/inventory"
	if [ ${DEEPOPS_FULL_INSTALL} ]; then
	  cp "${VIRT_DIR}/virtual_inventory_full" "${DEEPOPS_CONFIG_DIR}/inventory"
	fi
fi

# Clear any stale fact cache in Ansible
ansible -m meta -a "clear_facts" -i "${DEEPOPS_CONFIG_DIR}/inventory" all

# Set up Kubernetes (enabled by default)
if [ -z "${DEEPOPS_DISABLE_K8S}" ]; then
	"${VIRT_DIR}"/scripts/setup_k8s.sh
fi

# Set up Slurm (disabled by default)
if [ -n "${DEEPOPS_ENABLE_SLURM}" ]; then
	"${VIRT_DIR}"/scripts/setup_slurm.sh
fi
