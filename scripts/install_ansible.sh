#!/usr/bin/env bash

type ansible >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    sudo apt-add-repository -y ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get -y install ansible
    ansible --version
fi

