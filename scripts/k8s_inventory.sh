#!/usr/bin/env bash

git submodule update --init

k8s_config_dir=${K8S_CONFIG_DIR:-./k8s-config}

if [ ! -d "${k8s_config_dir}" ] ; then
	# Copy the kubespray default configuration
	cp -rfp kubespray/inventory/sample/ "${k8s_config_dir}"
fi

CONFIG_FILE=${k8s_config_dir}/hosts.ini python3 kubespray/contrib/inventory_builder/inventory.py ${@}
