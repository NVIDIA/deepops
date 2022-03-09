#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Install the optional kfp package
sudo pip3 install kfp

# Wait for the kubeflow pipeline service to be ready
./scripts/k8s/deploy_kubeflow.sh -w

kubectl get pods -n kubeflow # Do this for debug purposes

# Run the Kubeflow pipeline test, this will build a pipeline that launches an NGC container
# For some reason the initial pipeline creation hangs sometime (and doesn't timeout or error out or provide any logging) so we run this twice until success or timeout
python3 workloads/jenkins/scripts/test-kubeflow-pipeline.py
kubectl get pods -n kubeflow # Do this for debug purposes

# Delete Kubflow and view namespaces
./scripts/k8s/deploy_kubeflow.sh -d
kubectl get ns
