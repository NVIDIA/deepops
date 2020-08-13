#!/bin/bash
set -ex
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}" || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

# Verify Nodes & run single GPU test
kubectl get nodes
kubectl describe nodes

# Occassionally this gpu-test fails and/or hangs. To ease debugging of this we run a describe several seconds into the launch.
sleep 10 && kubectl describe pods gpu-test &
timeout 300 kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Run multi-GPU test
if [ "${DEEPOPS_FULL_INSTALL}" ]; then
  export CLUSTER_VERIFY_EXPECTED_PODS=${CLUSTER_VERIFY_EXPECTED_PODS:-2}
  timeout 300 ./scripts/k8s_verify_gpu.sh
fi
