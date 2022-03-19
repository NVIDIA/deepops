#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh
#cp /var/lib/jenkins/kustomize ${ROOT_DIR}/config # kustomize is saved off on the Jenkins server because the kustomize servers often rate-limit causing failed downloads

# Ensure working directory is root
cd "${ROOT_DIR}"

# Before deploying Kubeflow, clean up any unused Docker images to ensure we have sufficient space
ansible k8s-cluster -i "${VIRT_DIR}/config/inventory" -b -m shell -a "docker image prune -a --force"

# Deploy Kubflow
bash -x ./scripts/k8s/deploy_kubeflow.sh

# Wait for Kubeflow to be up
source ./scripts/k8s/deploy_kubeflow.sh -w

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~5 minutes for all pods and services to start, so we poll
timeout=600
time=0
while [ ${time} -lt ${timeout} ]; do
  curl -s --raw -L "${kf_url}" && \
    echo "Kubeflow is homepage is up " && exit 0 # Rather than poll here, we wait for the later kubeflow-pipeline test to poll and proceed to save testing time; kubeflow will continue coming up as monitoring and k8s dashboard tests run
  let time=$time+15
  sleep 15
done
curl -s --raw -L "${kf_url}" || exit 1 # If Kubeflow didn't come up in 600 seconds, fail
