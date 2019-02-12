#!/usr/bin/env bash

. /etc/os-release

case "$ID_LIKE" in
    rhel*)
        type ansible >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo yum -y install ansible
        fi
        ansible --version

        python -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo yum -y install ansible python-netaddr
        fi
        ;;
    debian*)
        type apt-add-repository >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt-get update
            sudo apt-get -y install software-properties-common
        fi

        type ansible >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt-add-repository -y ppa:ansible/ansible
            sudo apt-get update
            sudo apt-get -y install ansible
        fi
        ansible --version

        python -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt-get -y install python-netaddr
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac
