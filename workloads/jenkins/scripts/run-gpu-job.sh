#!/bin/bash
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}" || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

# Verify Nodes & run single GPU test
kubectl get nodes
kubectl describe nodes

# Verify GPU Feature Discovery was installed and one or more nodes were labeled, run queries and remove new lines/white space/non-gpu node output
strategy=$(kubectl get node -o=custom-columns=:.metadata.labels.nvidia\\.com/mig\\.strategy | grep -v none | tr -d '\040\011\012\015')
product=$(kubectl get node -o=custom-columns=:.metadata.labels.nvidia\\.com/gpu\\.product | grep -v none | tr -d '\040\011\012\015')

if [[ "${strategy}" != *"mixed"* ]] || [[ "${product}" == "" ]]; then # Using *mixed* because multiple GPU nodes mixed will show up multiple times
  echo "Expected GPU Feature Discovery to tag all GPU nodes, node 1 has nvidia.com/mig.strategy of '${strategy}'"
  echo "Expected GPU Feature Discovery to tag all GPU nodes, node 1 has nvidia.com/gpu.product of '${product}'"
  exit 2
fi

# Occassionally this gpu-test fails and/or hangs. To ease debugging of this we run a describe several seconds into the launch.
sleep 10 && kubectl describe pods gpu-test &
timeout 300 kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi

# Run multi-GPU test
if [ "${DEEPOPS_FULL_INSTALL}" ]; then
  export CLUSTER_VERIFY_EXPECTED_PODS=${CLUSTER_VERIFY_EXPECTED_PODS:-2}
  timeout 300 ./scripts/k8s/verify_gpu.sh
fi
