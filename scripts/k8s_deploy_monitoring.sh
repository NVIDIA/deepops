#!/usr/bin/env bash

# Ensure we start in the correct working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
cd "${ROOT_DIR}" || exit 1

HELM_COREOS_CHART_REPO="${HELM_COREOS_CHART_REPO:-https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/}"

# Determine DeepOps config dir
config_dir="$(pwd)/config"
if [ "${DEEPOPS_CONFIG_DIR}" ]; then
    config_dir="${DEEPOPS_CONFIG_DIR}"
elif [ -d "$(pwd)/config" ] ; then
    config_dir="$(pwd)/config"
fi

case "$1" in
    delete)
        helm del --purge prometheus-operator
        helm del --purge kube-prometheus
        kubectl delete ns monitoring
        exit 0
        ;;
esac

# Get IP of first master
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

./scripts/install_helm.sh

case "$1" in
    delete)
        helm del --purge prometheus-operator
        helm del --purge kube-prometheus
        kubectl delete ns monitoring
        exit 0
        ;;
esac

kubectl version
if [ $? -ne 0 ] ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
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

# Deploy the ingress controller with a set name
ingress_name="nginx-ingress"
NGINX_INGRESS_APP_NAME="${ingress_name}" ./scripts/k8s_deploy_ingress.sh

# Determine correct IP for ingress URL
ingress_ip_string="$(echo ${master_ip} | tr '.' '-').nip.io"
if kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' >/dev/null 2>&1; then
	lb_ip="$(kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' | awk '{print $3}')"
	ingress_ip_string="$(echo ${lb_ip} | tr '.' '-').nip.io"
	echo "Using load balancer url: ${ingress_ip_string}"
fi

# Deploy Monitoring stack
if ! helm status kube-prometheus >/dev/null 2>&1 ; then
    helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring --values ${config_dir}/helm/kube-prometheus.yml \
        --set alertmanager.ingress.hosts[0]="alertmanager-${ingress_ip_string}" \
        --set prometheus.ingress.hosts[0]="prometheus-${ingress_ip_string}" \
        --set grafana.ingress.hosts[0]="grafana-${ingress_ip_string}"
fi

# Label GPU nodes
for node in $(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com\\/gpu | grep -v none | awk '{print $1}') ; do
    kubectl label nodes ${node} hardware-type=NVIDIAGPU --overwrite >/dev/null
done

# Deploy DCGM node exporter
if kubectl -n monitoring get pod -l app=dcgm-exporter 2>&1 | grep "No resources found." >/dev/null 2>&1 ; then
    kubectl create -f services/dcgm-exporter.yml
fi

# Use NodePort directly if the IP string uses the master IP, otherwise use Ingress URL
if echo "${ingress_ip_string}" | grep "${master_ip}" >/dev/null 2>&1; then
	grafana_port=$(kubectl  -n monitoring get svc -l app=kube-prometheus-grafana --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
	prometheus_port=$(kubectl  -n monitoring get svc -l app=prometheus --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
	alertmanager_port=$(kubectl  -n monitoring get svc -l app=alertmanager --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
	echo
	echo "Grafana: http://${master_ip}:${grafana_port}/"
	echo "Prometheus: http://${master_ip}:${prometheus_port}/"
	echo "Alertmanager: http://${master_ip}:${alertmananger_port}/"
else
	echo
	echo "Grafana: http://grafana-${ingress_ip_string}/"
	echo "Prometheus: http://prometheus-${ingress_ip_string}/"
	echo "Alertmanager: http://alertmanager-${ingress_ip_string}/"
fi
