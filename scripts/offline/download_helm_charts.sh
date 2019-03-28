#!/bin/bash
set -ex

HELM_REPO_URL="https://github.com/helm/charts"
HELM_DEST_DIR="${HELM_DEST_DIR:-/tmp/deepops/helm_charts}"

cd "${HELM_DEST_DIR}"
if ! git clone "${HELM_REPO_URL}"; then
	echo "Failed to clone helm charts repository"
	exit 1
fi
