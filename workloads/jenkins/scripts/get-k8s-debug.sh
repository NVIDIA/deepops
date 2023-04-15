#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is virtual, so downstream Ansible picks up the correct inventory
cd "${VIRT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl

#  Collect all the standard debug
${ROOT_DIR}/scripts/k8s/debug.sh

# Iterate over each .log file and pring to screen, ignoring the tar
for logfile in $(ls ./config/${logdir}/*log); do
    cat ${logfile}
done

# Get some basic info about all nodes
kubectl describe nodes
kubectl get nodes

# Get some basic info about all running pods
kubectl get pods -A -o wide
kubectl get daemonsets -A

# Get some logs from the GPU operator Pods
if [ ${DEEPOPS_K8S_OPERATOR} ]; then
  kubectl -n gpu-operator logs -l app=gpu-feature-discovery
  kubectl -n gpu-operator logs -l app=nvidia-driver-daemonset
  kubectl -n gpu-operator logs -l app=dcgm-exporter-daemonset
  kubectl -n gpu-operator logs -l app=nvidia-container-toolkit-daemonset
fi

# Get helm status (requires helm install)
helm list -aA
