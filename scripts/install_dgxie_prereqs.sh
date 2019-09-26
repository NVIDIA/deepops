#!/usr/bin/env bash

# install required software
sudo apt-get update
sudo apt-get install -y git ipmitool vim software-properties-common sshpass

# install docker
type docker >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce
    docker --version
fi

# install docker-compose
type docker-compose >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    sudo curl -L https://github.com/docker/compose/releases/download/1.17.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    docker-compose --version
fi

# install ansible
type ansible >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get -y install ansible
    ansible --version
fi

# configure ISO mount
grep DGXServer /etc/fstab
if [ $? -ne 0 ] ; then
    mkdir -p /mnt/3.1.2
    echo "${HOME}/DGXServer-3.1.2.170902_f8777e.iso    /mnt/3.1.2  iso9660  loop    0   0" | sudo tee -a /etc/fstab
fi

# remove SUDO password requirement
sudo sed -i "s/^\%sudo.*/\%sudo   ALL=\(ALL:ALL\) NOPASSWD: ALL/g" /etc/sudoers
