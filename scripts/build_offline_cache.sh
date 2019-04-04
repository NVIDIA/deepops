#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
DEEPOPS_CONFIG_DIR="${DEEPOPS_CONFIG_DIR:-${ROOT_DIR}/config.example}"
DEST_DIR="/tmp/deepops"
TARBALL="/tmp/deepops-archive.tar.bz2"
DEEPOPS_BUILD_TARBALL="${DEEPOPS_BUILD_TARBALL:-1}"

echo "Building an offline cache of DeepOps dependencies on the local host"

cd "${ROOT_DIR}" || exit 1
ansible-playbook \
	-i "${DEEPOPS_CONFIG_DIR}/inventory" \
	-e offline_cache_dir="${DEST_DIR}" \
	playbooks/build-offline-cache.yml

echo "Running Kubespray download"

cd "${ROOT_DIR}/kubespray" || exit 1
tmp_dir="${TEMPDIR:-/tmp}"
export K8S_CONFIG_DIR="${tmp_dir}/download-k8s-config"
"${ROOT_DIR}/scripts/k8s_inventory.sh" 127.0.0.1

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
	-e enable_network_policy=true \
	-e local_release_dir="${DEST_DIR}" \
	--tags download \
	--skip-tags upload,upgrade \
	cluster.yml

sudo chown -R "$(whoami)" "${DEST_DIR}"

if [ "${DEEPOPS_BUILD_TARBALL}" -ne 0 ]; then
	echo "Building a big tarball of everything"
	tar cjf "${TARBALL}" -C "${DEST_DIR}" .
fi
