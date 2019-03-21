#!/bin/bash
set -ex

# To destroy the virtual cluster, we just tear down all VMs
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${VIRT_DIR}" || exit 1
vagrant destroy -f
cd -

# List running VMs for crosscheck
virsh list
