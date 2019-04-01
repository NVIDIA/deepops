#!/usr/bin/env bash

git submodule update --init

k8s_config_dir=${K8S_CONFIG_DIR:-./k8s-config}
deepops_config=${DEEPOPS_CONFIG_DIR:-$(pwd)/config.example}

if [ ! -d "${k8s_config_dir}" ] ; then
	# Copy the kubespray default configuration
	cp -rfp kubespray/inventory/sample/ "${k8s_config_dir}"
fi

# Copy extra vars file from deepops config dir to k8s config dir for overrides
cp -v "${deepops_config}/kubespray_deepops_vars.yml" "${k8s_config_dir}/group_vars/all/deepops.yml"

CONFIG_FILE=${k8s_config_dir}/hosts.ini python3 kubespray/contrib/inventory_builder/inventory.py ${@}
