#!/bin/bash
set -x
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Install the optional kfp package
sudo pip3 install kfp

# Wait for the kubeflow pipeline service to be ready, and then wait another 30 seconds for other random Kubeflow initialization
# Don't wait for katib or a few other things that take longer to initialize
export KUBEFLOW_DEPLOYMENTS="profiles-deployment centraldashboard ml-pipeline minio mysql metadata-db"
./scripts/k8s_deploy_kubeflow.sh -w

kubectl get pods -n kubeflow # Do this for debug purposes

# Run the Kubeflow pipeline test, this will build a pipeline that launches an NGC container
# For some reason the initial pipeline creation hangs sometime (and doesn't timeout or error out or provide any logging) so we run this twice until success or timeout
python3 .jenkins-scripts/test-kubeflow-pipeline.py
kubectl get pods -n kubeflow # Do this for debug purposes
