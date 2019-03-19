#!/bin/bash
set -ex

# Get absolute path for script, and convenience vars for virtual and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VIRT_DIR="${SCRIPT_DIR}/.."

#####################################
# Set up VMs for virtual cluster
#####################################

# Create SSH key in default location if it doesn't exist
yes n | ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -C "" -N "" || echo "key exists"

# Default to using provided Ubuntu Vagrantfile
if [ -z "${DEEPOPS_VAGRANT_FILE}" ]; then
	DEEPOPS_VAGRANT_FILE="${VIRT_DIR}/Vagrantfile-ubuntu"
fi
cp "${DEEPOPS_VAGRANT_FILE}" "${VIRT_DIR}/Vagrantfile"

# Ensure we're in the right directory for Vagrant
cd "${VIRT_DIR}" || exit 1

# Make sure our environment is clean
vagrant global-status --prune

# Start vagrant via libvirt - set up the VMs
vagrant up --provider=libvirt

# Show the running VMs
virsh list

# Return to previous dir, if we were in any
cd -
