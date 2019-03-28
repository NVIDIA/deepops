#!/bin/bash
set -ex

HELM_REPO_URL="https://github.com/helm/charts"
HELM_DEST_DIR="${HELM_DEST_DIR:-/tmp/deepops/helm_charts}"

if [ ! -d "${HELM_DEST_DIR}" ]; then
	mkdir -p "${HELM_DEST_DIR}"
fi

cd "${HELM_DEST_DIR}"
if ! git clone --recursive "${HELM_REPO_URL}"; then
	echo "Failed to clone helm charts repository"
	exit 1
fi
