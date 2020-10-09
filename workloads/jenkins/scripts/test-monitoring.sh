#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Deploy Monitoring
source ./scripts/k8s/deploy_monitoring.sh

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~1 minutes for all pods and services to start, so we poll
timeout=600
time=0
while [ ${time} -lt ${timeout} ]; do
  curl -s --raw -L "${prometheus_url}"     | grep Prometheus && \
    curl -s --raw -L "${grafana_url}"      | grep Grafana && \
    curl -s --raw -L "${alertmanager_url}" | grep Alertmanager && \
    echo "Monitoring URLs are all responding" && \
    pass=true && break
  let time=$time+15
  sleep 15
done

# Fail if timed out
if [ "${pass}" != "true" ]; then
  echo "Timed out getting monitoring responses"
  curl -s --raw -L "${prometheus_url}"
  curl -s --raw -L "${grafana_url}"
  curl -s --raw -L "${alertmanager_url}"
  exit 1
fi

# Delete Monitoring
source ./scripts/k8s/deploy_monitoring.sh -d && exit 0

# Monitoring deployment failure
echo "Monitoring did not come up in time"
exit 1
