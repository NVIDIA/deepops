#!/bin/bash
set -ex

# Get absolute path for script, and convenience vars for virtual and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VIRT_DIR="${SCRIPT_DIR}/.."

#####################################
# Set up VMs for virtual cluster 
#####################################

# Ensure we're in the right directory for Vagrant
cd "${VIRT_DIR}" || exit 1

# Start vagrant via libvirt - set up the VMs
vagrant up --no-parallel --provider=libvirt
# Show the running VMs
virsh list

# Return to previous dir, if we were in any
cd -
