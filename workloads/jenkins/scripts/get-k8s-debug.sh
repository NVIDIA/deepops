#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl

# Get some basic info about all nodes
kubectl describe nodes
kubectl get nodes

# Get some basic info about all running pods
kubectl get pods -A -o wide
kubectl get daemonsets -A

# Get some logs from the GPU operator Pods
if [ ${DEEPOPS_K8S_OPERATOR} ]; then
  kubectl -n gpu-operator-resources logs -l app=gpu-feature-discovery
  kubectl -n gpu-operator-resources logs -l app=nvidia-driver-daemonset
  kubectl -n gpu-operator-resources logs -l app=dcgm-exporter-daemonset
  kubectl -n gpu-operator-resources logs -l app=nvidia-container-toolkit-daemonset
fi

# Get helm status (requires helm install)
helm list -aA
