#!/bin/bash

if [ -z "${GPUDATA+x}" ]; then
	echo "GPUDATA variable is not set, are we running in Jenkins?"
	echo "Bailing!"
	exit 1
fi

GPU="$(echo "${GPUDATA}" | cut -d"-" -f1)"
export GPU
BUS="$(echo "${GPUDATA}" | cut -d"-" -f2)"
export BUS

echo "modify GPU passthrough to point to this resource's GPU"
sed -i -e "s/#v.pci :bus => '0x08', :slot => '0x00', :function => '0x0'/v.pci :bus => '$BUS', :slot => '0x00', :function => '0x0'/g" virtual/Vagrant*

echo "modify CPU and RAM requirements"
git grep -lz "v.cpus = 2" virtual/ | xargs -0 sed -i -e "s/v.cpus = 2/v.cpus = 4/g"
git grep -lz "v.memory = 2048" virtual/ | xargs -0 sed -i -e "s/v.memory = 2048/v.memory = 16384/g"

echo "modify machine names and IPs"
git grep -lz virtual-mgmt virtual/ | xargs -0 sed -i -e "s/virtual-mgmt/virtual-mgmt-${GPU}/g"
git grep -lz virtual-login virtual/ | xargs -0 sed -i -e "s/virtual-login/virtual-login-${GPU}/g"
git grep -lz virtual-gpu01 virtual/ | xargs -0 sed -i -e "s/virtual-gpu01/virtual-gpu01-${GPU}/g"
git grep -lz 10.0.0.2 virtual/ | xargs -0 sed -i -e "s/10.0.0.2/10.0.0.2${GPU}/g"
git grep -lz 10.0.0.4 virtual/ | xargs -0 sed -i -e "s/10.0.0.4/10.0.0.4${GPU}/g"
git grep -lz 10.0.0.11 virtual/ | xargs -0 sed -i -e "s/10.0.0.11/10.0.0.11${GPU}/g"

echo "Also fix IPs in the load balancer config"
sed -i -e  "s/10\\.0\\.0\\.100-10\\.0\\.0\\.110$/10.0.0.1${GPU}0-10.0.0.1${GPU}9/g" config.example/helm/metallb.yml

echo "Increase debug scope for ansible-playbook commands"
sed -i -e "s/ansible-playbook/ansible-playbook -v/g" virtual/scripts/*
