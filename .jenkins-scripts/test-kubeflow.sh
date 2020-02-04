#!/bin/bash
set -ex
source jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Deploy Kubflow, fail if it takes longer than 15 minutes
timeout 900 ./scripts/k8s_deploy_kubeflow.sh
