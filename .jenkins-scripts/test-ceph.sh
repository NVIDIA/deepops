#!/bin/bash
set -ex
source jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Deploy rook, fail if it takes longer than 5 minutes
timeout 300 ./scripts/k8s_deploy_rook.sh

# Poll for completion, fail if it takes longer than 30 minutes
timeout 1800 ./scripts/ceph_poll.sh
