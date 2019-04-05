#!/usr/bin/env bash

HELM_COREOS_CHART_REPO="${HELM_COREOS_CHART_REPO:-https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/}"

# Determine DeepOps config dir
config_dir="$(pwd)/config"
if [ "${DEEPOPS_CONFIG_DIR}" ]; then
    config_dir="${DEEPOPS_CONFIG_DIR}"
elif [ -d "$(pwd)/config" ] ; then
    config_dir="$(pwd)/config"
fi

# Get IP of first master
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

./scripts/install_helm.sh

# Add repo for Prometheus charts
if ! helm repo list | grep coreos >/dev/null 2>&1 ; then
    helm repo add coreos "${HELM_COREOS_CHART_REPO}"
fi

# Install Prometheus Operator
if ! helm status prometheus-operator >/dev/null 2>&1 ; then
    helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring --values ${config_dir}/helm/prometheus-operator.yml
fi

# Create GPU Dashboard config map
if ! kubectl -n monitoring get configmap kube-prometheus-grafana-gpu >/dev/null 2>&1 ; then
    kubectl create configmap kube-prometheus-grafana-gpu --from-file=${config_dir}/gpu-dashboard.json -n monitoring
fi

# Deploy the ingress controller
if ! helm status nginx-ingress >/dev/null 2>&1; then
	helm install --name nginx-ingress --values "${config_dir}/helm/ingress.yml" stable/nginx-ingress
fi

# Deploy Monitoring stack
if ! helm status kube-prometheus >/dev/null 2>&1 ; then
    helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring --values ${config_dir}/helm/kube-prometheus.yml \
        --set alertmanager.ingress.hosts[0]=alertmanager-$(echo ${master_ip} | tr '.' '-').nip.io \
        --set prometheus.ingress.hosts[0]=prometheus-$(echo ${master_ip} | tr '.' '-').nip.io \
        --set grafana.ingress.hosts[0]=grafana-$(echo ${master_ip} | tr '.' '-').nip.io
fi

# Label GPU nodes
for node in $(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com\\/gpu | awk '{print $1}') ; do
    kubectl label nodes ${node} hardware-type=NVIDIAGPU --overwrite >/dev/null
done

# Deploy DCGM node exporter
if kubectl -n monitoring get pod -l app=dcgm-exporter 2>&1 | grep "No resources found." >/dev/null 2>&1 ; then
    kubectl create -f services/dcgm-exporter.yml
fi

# Print URLs
echo
echo "Grafana: http://grafana-$(echo ${master_ip} | tr '.' '-').nip.io"
echo "Prometheus: http://prometheus-$(echo ${master_ip} | tr '.' '-').nip.io"
echo "Alertmanager: http://alertmanager-$(echo ${master_ip} | tr '.' '-').nip.io"
