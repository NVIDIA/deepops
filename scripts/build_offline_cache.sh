#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
DEEPOPS_CONFIG_DIR="${DEEPOPS_CONFIG_DIR:-${ROOT_DIR}/config.example}"

echo "Building an offline cache of DeepOps dependencies on the local host"

cd "${ROOT_DIR}" || exit 1
ansible-playbook -i "${DEEPOPS_CONFIG_DIR}/offline_cache/localhost_inventory" playbooks/build-offline-cache.yml

echo "Running Kubespray download"

cd "${ROOT_DIR}/kubespray" || exit 1
tmp_dir="${TEMPDIR:-/tmp}"
export K8S_CONFIG_DIR="${tmp_dir}/download-k8s-config"

"${ROOT_DIR}/scripts/k8s_inventory.sh" localhost
ansible-playbook \
	-i "${K8S_CONFIG_DIR}/hosts.ini" \
	-e download_run_one=true \
	-e download_localhost=true \
	-e kubeadm_enabled=true \
	-e kubectl_localhost=true \
	-e kubeconfig_localhost=true \
	-e helm_enabled=true \
	-e cephfs_provisioner_enabled=true \
	-e registry_enabled=true \
	-e dashboard_enabled=true \
	-e local_release_dir="/tmp/deepops" \
	--tags download \
	--skip-tags upload,upgrade
