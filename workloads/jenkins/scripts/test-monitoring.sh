#!/bin/bash
# Install monitoring with persistance, verify it deletes, re-install without persistance, verify DCGM metrics, verify it deletes
# We disable/re-enable "-e" in this script because polling will error until service come up and we want to collect output and debug
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

# Deploy Monitoring
source ./scripts/k8s/deploy_monitoring.sh

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~1 minutes for all pods and services to start, so we poll
timeout=600
time=0
set +e # This polling is expected to fail, so remove the -e flag for the loop
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
set -e # The loop is done, and we got debug if it failed, re-enable fail on error

# Verify that the polling option agrees that things are up
./scripts/k8s/deploy_monitoring.sh -w

# TODO: Create a test to verify storage is persisting

# Delete Monitoring (this should take ~30 seconds)
./scripts/k8s/deploy_monitoring.sh -d
set +e
curl -s --raw -L "${prometheus_url}"     | grep Prometheus && \
  curl -s --raw -L "${grafana_url}"      | grep Grafana && \
  curl -s --raw -L "${alertmanager_url}" | grep Alertmanager && \
  echo "Monitoring URLs are all responding when they should have been deleted" && \
  exit 1
set -e

# Deploy Monitoring without persistent data (this should be faster because containers have already been downloaded)
source ./scripts/k8s/deploy_monitoring.sh -x

# The deployment script exports the http endpoints, verify it returns a 200
# It typically takes ~1 minutes for all pods and services to start, so we poll
timeout=600
time=0
set +e # This polling is expected to fail, so remove the -e flag for the loop
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
set -e # The loop is done, and we got debug if it failed, re-enable fail on error

# Get some debug for Pods that did/didn't come up and verify DCGM metrics
kubectl get all -n monitoring
bash -x ./workloads/jenkins/scripts/test-dcgm-metrics.sh slurm-node # We use slurm-node here because it is GPU only, kube-node includes the mgmt plane

# Delete Monitoring
./scripts/k8s/deploy_monitoring.sh -d

set +e
curl -s --raw -L "${prometheus_url}"     | grep Prometheus && \
  curl -s --raw -L "${grafana_url}"      | grep Grafana && \
  curl -s --raw -L "${alertmanager_url}" | grep Alertmanager && \
  echo "Monitoring URLs are all responding when they should have been deleted" && \
  exit 1
set -e
