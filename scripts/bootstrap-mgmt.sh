#!/usr/bin/env bash

type ansible >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get -y install ansible
    ansible --version
fi

# Install other dependencies
sudo apt -y install git python-pip ipmitool
sudo apt -y install python-netaddr python3-netaddr
ansible-galaxy install -r requirements.yml

# Verify packages
git --version > /dev/null && ansible --version > /dev/null && ipmitool -h  > /dev/null
if [ "${?}" == "0" ]; then
	echo "Successfully installed all dependencies."
else
	echo "Dependency installation failed."
fi
