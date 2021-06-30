#!/bin/bash
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}" || exit 1

# Deploy rook, fail if it takes longer than 5 minutes
timeout 300 ./scripts/k8s/deploy_rook.sh -x

# Poll for completion, fail if it takes longer than 30 minutes
timeout 1800 ./scripts/k8s/deploy_rook.sh -w

# Print Rook-Ceph information
timeout 60 ./scripts/k8s/deploy_rook.sh -p
