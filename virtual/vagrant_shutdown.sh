#!/bin/bash
set -x

# To destroy the virtual cluster, we just tear down all VMs
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${VIRT_DIR}" || exit 1
if vagrant destroy -f ; then
  echo "Destroyed cluster."
else
  echo "Unable to vagrant destroy. Manually removing the VMs."
  virsh destroy virtual_virtual-mgmt01
  virsh undefine virtual_virtual-mgmt01
  virsh vol-delete --pool default virtual_virtual-mgmt01.img
  virsh destroy virtual_virtual-login01
  virsh undefine virtual_virtual-login01
  virsh vol-delete --pool default virtual_virtual-login01.img
  virsh destroy virtual_virtual-gpu01
  virsh undefine virtual_virtual-gpu01
  virsh vol-delete --pool default virtual_virtual-gpu01.img
  if [ ${DEEPOPS_FULL_INSTALL} ]; then
    virsh destroy virtual_virtual-mgmt02
    virsh undefine virtual_virtual-mgmt02
    virsh vol-delete --pool default virtual_virtual-mgmt02.img
    virsh destroy virtual_virtual-mgmt03
    virsh undefine virtual_virtual-mgmt03
    virsh vol-delete --pool default virtual_virtual-mgmt03.img
    virsh destroy virtual_virtual-gpu02
    virsh undefine virtual_virtual-gpu02
    virsh vol-delete --pool default virtual_virtual-gpu02.img
  fi
fi
cd -

# List running VMs for crosscheck
virsh list
