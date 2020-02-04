#!/bin/bash

# Get absolute path for the virtual DeepOps directory
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${VIRT_DIR}/.."

# Ensure working directory is root
cd "${ROOT_DIR}"

K8S_CONFIG_DIR=${VIRT_DIR}/config
export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

kubectl get nodes
kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

if [ "${DEEPOPS_FULL_INSTALL}" ]; then
  export CLUSTER_VERIFY_EXPECTED_PODS=2
  # TODO: Uncomment when this PR is merged https://github.com/NVIDIA/deepops/pull/420 # ./scripts/k8s_verify_gpu.sh
fi
