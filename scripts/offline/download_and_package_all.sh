#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DEST_DIR="${DEST_DIR:-/tmp/deepops}"
TAR_FILE="${TAR_FILE:-/tmp/deepops-with-deps-$(date +"%m_%d_%Y").tar.gz}"

echo "Downloading DeepOps dependencies"
echo "Starting process at: $(date)"
sleep 1
REPO_DEST_DIR="${DEST_DIR}/deepops" "${SCRIPT_DIR}/fresh_deepops_repo.sh"
HELM_DEST_DIR="${DEST_DIR}/helm-charts" "${SCRIPT_DIR}/download_helm_charts.sh"
IMAGES_DEST_DIR="${DEST_DIR}/docker-images" "${SCRIPT_DIR}/download_docker_images.sh"
SYNC_DEST_DIR="${DEST_DIR}/yum-mirror" "${SCRIPT_DIR}/download_centos_repos.sh"

echo "Saving everything to a tar.gz file, this might take a long time..."
sleep 1
tar czf "${TAR_FILE}" "${DEST_DIR}"
echo "Finished at: $(date)"
