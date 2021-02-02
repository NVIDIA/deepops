#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
DEEPOPS_CONFIG_DIR="${DEEPOPS_CONFIG_DIR:-${ROOT_DIR}/config.example}"
DEST_DIR="/tmp/deepops"
TARBALL="/tmp/deepops-archive.tar"
DEEPOPS_BUILD_TARBALL="${DEEPOPS_BUILD_TARBALL:-1}"

echo "Preparing to download a cache of all DeepOps dependencies"
echo "You might want to go get lunch..."
mkdir -p "${DEST_DIR}"

#############################################################################
# Mechanism adapted from
# https://github.com/helm/chartmuseum/blob/master/scripts/mirror_k8s_repos.sh

if ! which ruby; then
    echo "ruby needed for fancy yaml parsing, please install"
    exit 1
fi

if ! which python3.6; then
    echo "python3.6 needed for Kubespray, please install"
    exit 1
fi

if ! docker ps; then
    echo "docker must be installed and running for Kubespray, please install/verify"
    exit 1
fi

if ! ls config; then
    echo "It looks like you have not run scripts/setup.sh, please see the README and run setup."
    exit 1
fi

get_all_helm_tgzs() {
    local repo_url="$1"
    rm -f index.yaml
    wget "$repo_url/index.yaml"
    tgzs="$(ruby -ryaml -e \
        "YAML.load_file('index.yaml')['entries'].each do |k,e|;for c in e;puts c['urls'][0];end;end")"
    pushd mirror/
    for tgz in $tgzs; do
        if [ ! -f "${tgz##*/}" ]; then
            wget "$tgz" >/dev/null 2>&1 || echo "Couldn't download ${tgz}, skipping..."
        fi
    done
    popd
}

echo "Mirroring Helm charts locally"
HELM_DEST_DIR="${HELM_DEST_DIR:-${DEST_DIR}/helm}"

HELM_STABLE_CHARTS_URL="${HELM_STABLE_CHARTS_URL:-https://charts.helm.sh/stable}"
HELM_ROOK_CHARTS_URL="${HELM_ROOK_CHARTS_URL:-https://charts.rook.io/master}"
HELM_JUPYTER_CHARTS_URL="${HELM_JUPYTER_CHARTS_URL:-https://jupyterhub.github.io/helm-chart}"

mkdir -p "${HELM_DEST_DIR}/mirror"
pushd "${HELM_DEST_DIR}"
get_all_helm_tgzs "${HELM_STABLE_CHARTS_URL}"
get_all_helm_tgzs "${HELM_ROOK_CHARTS_URL}"
get_all_helm_tgzs "${HELM_JUPYTER_CHARTS_URL}"
popd

#############################################################################
echo "Running Kubespray download"
tmp_dir="${TEMPDIR:-/tmp}"
export K8S_CONFIG_DIR="${tmp_dir}/download-k8s-config"
"${ROOT_DIR}/scripts/k8s_inventory.sh" 127.0.0.1
cd "${ROOT_DIR}/kubespray" || exit 1
mkdir -p "${DEST_DIR}/misc-files"
ansible-playbook -b \
	-i "${K8S_CONFIG_DIR}/hosts.ini" \
	-e download_run_one=true \
	-e download_localhost=true \
	-e kubectl_localhost=true \
	-e helm_enabled=true \
	-e cephfs_provisioner_enabled=true \
	-e dashboard_enabled=true \
        -e registry_enabled=true \
	-e local_release_dir="${DEST_DIR}/misc-files" \
	--tags download \
	--skip-tags upload,upgrade \
	cluster.yml

#############################################################################
echo "Downloading other DeepOps dependencies"
cd "${ROOT_DIR}" || exit 1
ansible-playbook \
	-e offline_cache_dir="${DEST_DIR}" \
	playbooks/airgap/build-offline-cache.yml

#############################################################################
sudo chown -R "$(whoami)" "${DEST_DIR}"
if [ "${DEEPOPS_BUILD_TARBALL}" -ne 0 ]; then
	echo "Building a big tarball of everything"
	tar cf "${TARBALL}" -C "${DEST_DIR}" .
fi
