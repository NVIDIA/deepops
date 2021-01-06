#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh
cp /var/lib/jenkins/kustomize ${ROOT_DIR}/config # kustomize is saved off on the Jenkins server because the kustomize servers often rate-limit causing failed downloads

# Ensure working directory is root
cd "${ROOT_DIR}"

export KF_DIR=${ROOT_DIR}/config/kubeflow
export KFCTL=${ROOT_DIR}/config/kfctl
export KUBEFLOW_DEPLOYMENTS="profiles-deployment centraldashboard ml-pipeline minio mysql metadata-db" # TODO: We will only poll for these, because other services currently fail to come up in Jenkins due to low disk space

# Deploy Kubflow with Dex
source ./scripts/k8s/deploy_kubeflow.sh -x

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~5 minutes for all pods and services to start, so we poll
timeout=600
time=0
while [ ${time} -lt ${timeout} ]; do
  curl -s --raw -L "${kf_url}" && \
    echo "Kubeflow is homepage is up " && break
  let time=$time+15
  sleep 15
done
curl -s --raw -L "${kf_url}" || exit 1 # If Kubeflow didn't come up in 600 seconds, fail

# Wait for it to come up and view pods
./scripts/k8s/deploy_kubeflow.sh -w
kubectl get pods -n kubeflow

# Delete Kubflow and view namespaces
./scripts/k8s/deploy_kubeflow.sh -d
kubectl get ns

# Deploy Kubflow
source ./scripts/k8s/deploy_kubeflow.sh

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
