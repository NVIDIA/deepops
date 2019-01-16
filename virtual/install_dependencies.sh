#!/bin/bash
set -xe

# install dependencies
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
sudo apt update
sudo apt install -y ansible

if [ "$(lsb_release -cs)" = "bionic" ]; then
    # dotless-de/vagrant-vbguest#292
    pushd "$(mktemp -d)"
    wget https://releases.hashicorp.com/vagrant/2.0.3/vagrant_2.0.3_x86_64.deb -O vagrant.deb
    sudo dpkg -i vagrant.deb
    popd
else
    sudo apt install -y vagrant
fi

sudo apt install -y python-netaddr
sudo apt install -y sshpass

# install kvm packages
sudo apt install -y qemu-kvm libvirt-bin libvirt-dev bridge-utils libguestfs-tools
sudo apt install -y qemu ovmf virt-manager firewalld

# install vagrant plugins
vagrant plugin install vagrant-hostmanager vagrant-libvirt
vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate


