#!/bin/bash
# Verify that the DCGM-exporter is returning all metrics configured in the Grafana dashboard, for each node
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

DCGM_EXPORTER_PORT=9400

# Run DCGM metric checks against all nodes in the group passed in (kube-node or slurm-node)
group="${1}"

# DCGM-exporter takes some time to initialize after it has started up
# Before checking specific metrics we poll for any DCGM metrics to return
set +e
timeout=500
time=0
set +e # This polling is expected to fail, so remove the -e flag for the loop
while [ ${time} -lt ${timeout} ]; do
# Collect metrics from all nodes for debug
  ansible ${group} -vv -m raw \
    -u vagrant \
    ${ansible_extra_args} \
    -b -i "virtual/config/inventory" \
    -a "curl http://127.0.0.1:${DCGM_EXPORTER_PORT}/metrics | grep DCGM" && break
    let time=$time+5
    sleep 5
done
set -e

# Collect metrics from all nodes for debug
ansible ${group} -vv -m raw \
  -b -i "virtual/config/inventory" \
  -u vagrant \
  ${ansible_extra_args} \
  -a "curl http://127.0.0.1:${DCGM_EXPORTER_PORT}/metrics"

# Get an up-to-date list of all DCGM metrics included in the default dashboard, with some awk magic
dcgm_metrics=$(grep DCGM ${ROOT_DIR}/src/dashboards/gpu-dashboard.json   | awk -F\{ '{print $1}' | awk -F"DCGM" '{print "DCGM"$2}' | sort | uniq)

# Verify all DCGM metrics from the default dashboard are being returned by the DCGM-exporter
for metric in ${dcgm_metrics}; do
  ansible ${group} -vv -m raw \
    -b -i "virtual/config/inventory" \
    -u vagrant \
    ${ansible_extra_args} \
    -a "curl http://127.0.0.1:${DCGM_EXPORTER_PORT}/metrics | grep ${metric}" # TODO: optimize this by doing a single curl call per metric
done
