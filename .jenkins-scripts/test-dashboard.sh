#!/bin/bash
set -x
source .jenkins-scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Deploy Dashboard
source ./scripts/k8s_deploy_dashboard_user.sh

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~1 minutes for all pods and services to start, so we poll
timeout=120
time=0
while [ ${time} -lt ${timeout} ]; do
  curl -ks --raw -kL "${dashboard_url}" | grep "Kubernetes Dashboard" && \
    echo "Dashboard URLs are all responding" && exit 0
  let time=$time+15
  sleep 15
done

# Dashboard deployment failure
echo "Dashboard did not come up in time"
exit 1
