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
./scripts/setup.sh

# Ensure clean config dirs for a new turnup
DEEPOPS_VIRT_CLEAN_CONFIG="${DEEPOPS_VIRT_CLEAN_CONFIG:-1}"
if [ "${DEEPOPS_VIRT_CLEAN_CONFIG}" -ne 0 ]; then
	rm -rf "${VIRT_DIR}/config"
	rm -rf "${VIRT_DIR}/k8s-config"
fi

# Create the config for deepops servers (and use the virtual inventory)
export DEEPOPS_CONFIG_DIR="${VIRT_DIR}/config"
cp -r "${ROOT_DIR}/config.example/" "${DEEPOPS_CONFIG_DIR}/"
cp "${VIRT_DIR}/virtual_inventory" "${DEEPOPS_CONFIG_DIR}/inventory"

# Clear any stale fact cache in Ansible
ansible -m meta -a "clear_facts" -i "${DEEPOPS_CONFIG_DIR}/inventory" all

# Optionally force DNS config to be sane
DEEPOPS_FORCE_DNS="${DEEPOPS_FORCE_DNS:-1}"
if [ "${DEEPOPS_FORCE_DNS}" -ne 0 ]; then
	"${VIRT_DIR}/scripts/force_dns_config.sh"
fi

# Set up Kubernetes (enabled by default)
if [ -z "${DEEPOPS_DISABLE_K8S}" ]; then
	"${VIRT_DIR}"/scripts/setup_k8s.sh
fi

# Set up Slurm (disabled by default)
if [ -n "${DEEPOPS_ENABLE_SLURM}" ]; then
	"${VIRT_DIR}"/scripts/setup_slurm.sh
fi
