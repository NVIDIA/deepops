#!/bin/bash
set -x
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl

# Deploy Kubflow
source ./scripts/k8s_deploy_kubeflow.sh

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~5 minutes for all pods and services to start, so we poll
timeout=600
time=0
while [ ${time} -lt ${timeout} ]; do
  curl -s --raw -L "${kf_url}" && \
    echo "Kubeflow is homepage is up " && exit 0
  let time=$time+15
  sleep 15
done

# Kubeflow deployment failure
echo "Kubeflow did not come up in time"
exit 1
