#!/bin/bash
set -ex

# To destroy the virtual cluster, we just tear down all VMs
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${VIRT_DIR}" || exit 1
if vagrant destroy -f ; then
  echo "Destroyed cluster."
else
  echo "Unable to vagrant destroy. Manually removing the VMs."
  virsh destroy virtual_virtual-mgmt
  virsh undefine virtual_virtual-mgmt
  virsh vol-delete --pool default virtual_virtual-mgmt.img
  virsh destroy virtual_virtual-login
  virsh undefine virtual_virtual-login
  virsh vol-delete --pool default virtual_virtual-login.img
  virsh destroy virtual_virtual-gpu01
  virsh undefine virtual_virtual-gpu01
  virsh vol-delete --pool default virtual_virtual-gpu01.img
fi
cd -

# List running VMs for crosscheck
virsh list
