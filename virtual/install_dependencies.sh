#!/bin/bash
set -xe

# install dependencies
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
sudo apt update
sudo apt install -y ansible
sudo apt install -y vagrant
sudo pip install netaddr

# install kvm packages
sudo apt install -y qemu-kvm libvirt-bin bridge-utils libguestfs-tools
sudo apt install -y qemu ovmf virt-manager firewalld

# install vagrant plugins
vagrant plugin install vagrant-hostmanager vagrant-libvirt
vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate


