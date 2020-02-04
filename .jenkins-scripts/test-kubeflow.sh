#!/bin/bash
set -ex
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl

# Deploy Kubflow, fail if it takes longer than 15 minutes
timeout 900 ./scripts/k8s_deploy_kubeflow.sh
