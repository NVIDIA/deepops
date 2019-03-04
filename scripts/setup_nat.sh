#!/usr/bin/env bash

export HOST_INT_PUB="${1}"
export HOST_INT_PRV="${2}"

ip a show dev "${HOST_INT_PUB}"
if [ $? -ne 0 ] ; then
    exit 1
fi

ip a show dev "${HOST_INT_PRV}"
if [ $? -ne 0 ] ; then
    exit 1
fi

set -x
sudo /sbin/iptables -t nat -A POSTROUTING -o ${HOST_INT_PUB} -j MASQUERADE
sudo /sbin/iptables -A FORWARD -i ${HOST_INT_PUB} -o ${HOST_INT_PRV} -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo /sbin/iptables -A FORWARD -i ${HOST_INT_PRV} -o ${HOST_INT_PUB} -j ACCEPT
sudo sysctl -w net.ipv4.ip_forward=1
set +x
