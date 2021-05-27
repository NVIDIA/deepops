#!/bin/bash
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"


DCGM_EXPORTER_PORT=9400


# Get an up-to-date list of all DCGM metrics included in the default dashboard, with some awk magic
dcgm_metrics=$(grep DCGM ${ROOT_DIR}/src/dashboards/gpu-dashboard.json   | awk -F\{ '{print $1}' | awk -F"DCGM" '{print "DCGM"$2}' | sort | uniq)

# Verify all DCGM metrics from the default dashboard are being returned by the DCGM-exporter
for metric in ${dcgm_metrics}; do
  ansible kube-node -vv -m raw \
    -b -i "virtual/config/inventory" \
    -e "@virtual/vars_files/virt_k8s.yml" \
    ${ansible_extra_args} \
    -a "curl http://127.0.0.1:${DCGM_EXPORTER_PORT}/metrics | grep ${metric}" # TODO: optimize this by doing a single curl call per metric
done
