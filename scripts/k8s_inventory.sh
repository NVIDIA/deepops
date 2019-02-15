#!/usr/bin/env bash

k8s_config_dir=./k8s-config

if [ ! -d "${k8s_config_dir}" ] ; then
	# Copy the kubespray default configuration
	cp -rfp kubespray/inventory/sample/ "${k8s_config_dir}"
fi

CONFIG_FILE=k8s-config/hosts.ini python3 kubespray/contrib/inventory_builder/inventory.py ${@}
