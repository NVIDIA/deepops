#!/usr/bin/env bash

HELM_COREOS_CHART_REPO="${HELM_COREOS_CHART_REPO:-https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/}"

type helm >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    ./scripts/install_helm.sh
fi

# Add repo for prometheus charts
helm repo list | grep coreos >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm repo add coreos "${HELM_COREOS_CHART_REPO}"
fi

# Determine DeepOps config dir
config_dir="$(pwd)/config.example"
if [ "${DEEPOPS_CONFIG_DIR}" ]; then
    config_dir="${DEEPOPS_CONFIG_DIR}"
fi

# Install Prometheus Operator
helm status prometheus-operator >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring --values ${config_dir}/helm/prometheus-operator.yml
fi

# Create GPU Dashboard config map
kubectl -n monitoring get configmap kube-prometheus-grafana-gpu >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    kubectl create configmap kube-prometheus-grafana-gpu --from-file=${config_dir}/gpu-dashboard.json -n monitoring
fi

# Deploy Monitoring stack
helm status kube-prometheus >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring --values ${config_dir}/helm/kube-prometheus.yml
fi

# Label GPU nodes
for node in $(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com\\/gpu | awk '{print $1}') ; do
    kubectl label nodes ${node} hardware-type=NVIDIAGPU --overwrite >/dev/null
done

kubectl -n monitoring get pod -l app=dcgm-exporter 2>&1 | grep "No resources found." >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    kubectl create -f services/dcgm-exporter.yml
fi

# Get IP of first master
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# Get Grafana port
grafana_port=$(kubectl  -n monitoring get svc -l app=kube-prometheus-grafana --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)

# Print Grafana address
echo "Grafana is available at: http://${master_ip}:${grafana_port}"
