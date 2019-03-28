#!/bin/bash
set -ex

DEEPOPS_REPO_URL="${DEEPOPS_REPO_URL:-https://github.com/NVIDIA/deepops}"
REPO_DEST_DIR="${REPO_DEST_DIR:-/tmp/deepops/deepops}"

if [ -d "${REPO_DEST_DIR}" ]; then
	rm -rf "${REPO_DEST_DIR}"
fi
mkdir -p "${REPO_DEST_DIR}"

git clone --recursive "${DEEPOPS_REPO_URL}" "${REPO_DEST_DIR}"

(
  cd "${REPO_DEST_DIR}" && \
  ansible-galaxy install -p "${REPO_DEST_DIR}/ansible-galaxy" -r requirements.yml
)
