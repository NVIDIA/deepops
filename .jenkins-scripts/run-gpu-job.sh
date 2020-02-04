#!/bin/bash
set -ex
source jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

# Verify Nodes & run single GPU test
kubectl get nodes
kubectl run gpu-test --pod-running-timeout=2m0s --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Run multi-GPU test
if [ "${DEEPOPS_FULL_INSTALL}" ]; then
  export CLUSTER_VERIFY_EXPECTED_PODS=2
  # TODO: Uncomment when this PR is merged https://github.com/NVIDIA/deepops/pull/420 # ./scripts/k8s_verify_gpu.sh
fi
