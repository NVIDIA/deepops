#!/bin/bash

if [ -z "${GPUDATA+x}" ]; then
	echo "GPUDATA variable is not set, are we running in Jenkins?"
	echo "Bailing!"
	exit 1
fi

GPU01="$(echo "${GPUDATA}" | cut -d"," -f1 | cud -d"-" -f1)"
export GPU01
BUS01="$(echo "${GPUDATA}" | cud -d"," -f1 | cut -d"-" -f2)"
export BUS01
GPU02="$(echo "${GPUDATA}" | cut -d"," -f2 | cud -d"-" -f1)"
export GPU02
BUS02="$(echo "${GPUDATA}" | cud -d"," -f2 | cut -d"-" -f2)"
export BUS02

# comment in for pci passthrough (and change bus according to local hw setup - `lspci -nnk | grep NVIDIA`)
echo "modify GPU passthrough to point to this resource's GPU: ${GPU01}/${GPU02} and BUS: ${BUS01}/${BUS02} based on: ${GPUDATA}"
sed -i -e "s/BUS-GPU01.*/v.pci :bus => '$BUS01', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant*
sed -i -e "s/BUS-GPU02.*/v.pci :bus => '$BUS02', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant* # This is a no-op if not full-install

echo "modify CPU and RAM requirements"
git grep -lz "v.cpus = 2" virtual/ | xargs -0 sed -i -e "s/v.cpus = 2/v.cpus = 4/g"
git grep -lz "v.memory = 2048" virtual/ | xargs -0 sed -i -e "s/v.memory = 2048/v.memory = 16384/g"

# We append the index of GPU01 to each IP address to ensure uniqueness across the 4 GPU Node
# This allows us to assign IP addresses from 10.0.x.[1-24] before breaking.
echo "modify machine names and IPs" # mgmt01, login, gpu01
git grep -lz virtual-mgmt01 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt01/virtual-mgmt01-${GPU01}/g"
git grep -lz virtual-login virtual/ | xargs -0 sed -i -e "s/virtual-login/virtual-login-${GPU01}/g"
git grep -lz virtual-gpu01 virtual/ | xargs -0 sed -i -e "s/virtual-gpu01/virtual-gpu01-${GPU01}/g"
git grep -lz 10.0.0.2 virtual/ | xargs -0 sed -i -e "s/10.0.0.2/10.0.0.2${GPU01}/g"
git grep -lz 10.0.0.4 virtual/ | xargs -0 sed -i -e "s/10.0.0.4/10.0.0.4${GPU01}/g"
git grep -lz 10.0.0.11 virtual/ | xargs -0 sed -i -e "s/10.0.0.11/10.0.0.11${GPU01}/g"
if [ -z ${DEEPOPS_FULL_INSTALL} ]; then # mgmt02, mgmt03, gpu02
  git grep -lz virtual-mgmt02 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt02/virtual-mgmt02-${GPU01}/g"
  git grep -lz virtual-mgmt03 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt03/virtual-mgmt03-${GPU01}/g"
  git grep -lz virtual-gpu02 virtual/ | xargs -0 sed -i -e "s/virtual-gpu01/virtual-gpu02-${GPU01}/g"
  git grep -lz 10.0.0.3 virtual/ | xargs -0 sed -i -e "s/10.0.0.3/10.0.0.3${GPU01}/g"
  git grep -lz 10.0.0.5 virtual/ | xargs -0 sed -i -e "s/10.0.0.5/10.0.0.5${GPU01}/g"
  git grep -lz 10.0.0.12 virtual/ | xargs -0 sed -i -e "s/10.0.0.12/10.0.0.12${GPU01}/g"
fi

echo "Also fix IPs in the load balancer config"
sed -i -e  "s/10\\.0\\.0\\.100-10\\.0\\.0\\.110$/10.0.0.1${GPU01}0-10.0.0.1${GPU01}9/g" config.example/helm/metallb.yml

echo "Increase debug scope for ansible-playbook commands"
sed -i -e "s/ansible-playbook/ansible-playbook -v/g" virtual/scripts/*
