#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# comment in for pci passthrough (and change bus according to local hw setup - `lspci -nnk | grep NVIDIA`)
echo "modify GPU passthrough to point to this resource's GPU: ${GPU01}/${GPU02} and BUS: ${BUS01}/${BUS02} based on: ${GPUDATA}"
sed -i -e "s/#BUS-GPU01.*/v.pci :bus => '$BUS01', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant*
sed -i -e "s/#BUS-GPU02.*/v.pci :bus => '$BUS02', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant* # This is a no-op if not full-install

echo "modify CPU and RAM requirements"
git grep -lz "v.cpus = 2" virtual/ | xargs -0 sed -i -e "s/v.cpus = 2/v.cpus = 4/g" # login01
git grep -lz "v.memory = 2048" virtual/ | xargs -0 sed -i -e "s/v.memory = 2048/v.memory = 16384/g" # login01
git grep -lz "v.memory = 4096" virtual/ | xargs -0 sed -i -e "s/v.memory = 4096/v.memory = 16384/g" # mgmt01

# We append the index of GPU01 to each IP address to ensure uniqueness across the 4 GPU Node
# This allows us to assign IP addresses from 10.0.x.[1-24] before breaking.
echo "modify machine names and IPs" # mgmt01, login01, gpu01
git grep -lz virtual-mgmt01 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt01/virtual-mgmt01-${GPU01}/g"
git grep -lz virtual-login01 virtual/ | xargs -0 sed -i -e "s/virtual-login01/virtual-login01-${GPU01}/g"
git grep -lz virtual-gpu01 virtual/ | xargs -0 sed -i -e "s/virtual-gpu01/virtual-gpu01-${GPU01}/g"
git grep -lz 10.0.0.2 virtual/ | xargs -0 sed -i -e "s/10.0.0.2/10.0.0.2${GPU01}/g"
git grep -lz 10.0.0.5 virtual/ | xargs -0 sed -i -e "s/10.0.0.5/10.0.0.5${GPU01}/g"
git grep -lz 10.0.0.6 virtual/ | xargs -0 sed -i -e "s/10.0.0.6/10.0.0.6${GPU01}/g"
if [ ${DEEPOPS_FULL_INSTALL} ]; then # mgmt02, mgmt03, gpu02
  git grep -lz virtual-mgmt02 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt02/virtual-mgmt02-${GPU01}/g"
  git grep -lz virtual-mgmt03 virtual/ | xargs -0 sed -i -e "s/virtual-mgmt03/virtual-mgmt03-${GPU01}/g"
  git grep -lz virtual-gpu02 virtual/ | xargs -0 sed -i -e "s/virtual-gpu02/virtual-gpu02-${GPU01}/g"
  git grep -lz 10.0.0.3 virtual/ | xargs -0 sed -i -e "s/10.0.0.3/10.0.0.3${GPU01}/g"
  git grep -lz 10.0.0.4 virtual/ | xargs -0 sed -i -e "s/10.0.0.4/10.0.0.4${GPU01}/g"
  git grep -lz 10.0.0.7 virtual/ | xargs -0 sed -i -e "s/10.0.0.7/10.0.0.7${GPU01}/g"
fi

echo "Also fix IPs in the load balancer config"
sed -i -e  "s/10\\.0\\.0\\.100-10\\.0\\.0\\.110$/10.0.0.1${GPU01}0-10.0.0.1${GPU01}9/g" config.example/helm/metallb.yml

echo "Increase debug scope for ansible-playbook commands"
sed -i -e "s/ansible-playbook/ansible-playbook -v/g" virtual/scripts/*
