#!/bin/bash
set -xe

# install dependencies
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
sudo apt update
sudo apt install -y ansible
sudo apt install -y virtualbox virtualbox-ext-pack vagrant
sudo pip install netaddr

# install vagrant plugins
vagrant plugin install vagrant-hostmanager vagrant-libvirt
vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate


