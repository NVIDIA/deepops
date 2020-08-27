#!/bin/bash
set -x
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl

# Get some basic info about all nodes
kubectl describe nodes
kubectl get nodes

# Get some basic info about all running pods
kubectl get pods -A
kubectl get daemonsets -A

# Get helm status (requires helm install)
helm list
