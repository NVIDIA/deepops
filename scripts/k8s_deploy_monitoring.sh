#!/usr/bin/env bash

# Ensure we start in the correct working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
cd "${ROOT_DIR}" || exit 1

# Determine DeepOps config dir
config_dir="$(pwd)/config"
if [ "${DEEPOPS_CONFIG_DIR}" ]; then
    config_dir="${DEEPOPS_CONFIG_DIR}"
elif [ -d "$(pwd)/config" ] ; then
    config_dir="$(pwd)/config"
fi

HELM_CHARTS_REPO_STABLE="${HELM_CHARTS_REPO_STABLE:-https://kubernetes-charts.storage.googleapis.com}"
HELM_PROMETHEUS_CHART_VERSION="${HELM_PROMETHEUS_CHART_VERSION:-8.15.0}"
ingress_name="nginx-ingress"

case "$1" in
    delete)
        helm del --purge prometheus-operator
        helm del --purge "${ingress_name}"
        kubectl delete crd prometheuses.monitoring.coreos.com
        kubectl delete crd prometheusrules.monitoring.coreos.com
        kubectl delete crd servicemonitors.monitoring.coreos.com
        kubectl delete crd podmonitors.monitoring.coreos.com
        kubectl delete crd alertmanagers.monitoring.coreos.com
        kubectl delete crd thanosrulers.monitoring.coreos.com
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

# Install/initialize Helm if needed
./scripts/install_helm.sh

# Add Helm stable repo if it doesn't exist
if ! helm repo list | grep stable >/dev/null 2>&1 ; then
    helm repo add stable "${HELM_CHARTS_REPO_STABLE}"
fi

# Configure air-gapped deployment
helm_prom_oper_args=""
if [ "${PROMETHEUS_OPER_REPO}" ]; then
    helm_prom_oper_args="${helm_prom_oper_args} --set-string image.repository="${PROMETHEUS_OPER_REPO}""
fi
helm_kube_prom_args=""
if [ "${ALERTMANAGER_REPO}" ]; then
    helm_kube_prom_args="${helm_kube_prom_args} --set-string alertmanager.image.repository="${ALERTMANAGER_REPO}""
fi
if [ "${PROMETHEUS_REPO}" ]; then
    helm_kube_prom_args="${helm_kube_prom_args} --set-string prometheus.image.repository="${PROMETHEUS_REPO}""
fi
if [ "${GRAFANA_REPO}" ]; then
    helm_kube_prom_args="${helm_kube_prom_args} --set-string grafana.image.repository="${GRAFANA_REPO}""
fi
if [ "${GRAFANA_WATCHER_REPO}" ]; then
    helm_kube_prom_args="${helm_kube_prom_args} --set-string grafana.grafanaWatcher.repository="${GRAFANA_WATCHER_REPO}""
fi

# Deploy the ingress controller with a set name
NGINX_INGRESS_APP_NAME="${ingress_name}" ./scripts/k8s_deploy_ingress.sh

# Determine correct IP for ingress URL
ingress_ip_string="$(echo ${master_ip} | tr '.' '-').nip.io"
if kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' >/dev/null 2>&1; then
    lb_ip="$(kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' | awk '{print $3}')"
    ingress_ip_string="$(echo ${lb_ip} | tr '.' '-').nip.io"
    echo "Using load balancer url: ${ingress_ip_string}"
fi

# Deploy Monitoring stack via Prometheus Operator Helm chart
echo
echo "Deploying monitoring stack..."
if ! helm status prometheus-operator >/dev/null 2>&1 ; then
    helm install \
        stable/prometheus-operator \
        --version "${HELM_PROMETHEUS_CHART_VERSION}" \
        --name prometheus-operator \
        --namespace monitoring \
        --values ${config_dir}/helm/monitoring.yml \
        --set alertmanager.ingress.hosts[0]="alertmanager-${ingress_ip_string}" \
        --set prometheus.ingress.hosts[0]="prometheus-${ingress_ip_string}" \
        --set grafana.ingress.hosts[0]="grafana-${ingress_ip_string}" \
        ${helm_prom_oper_args} \
        ${helm_kube_prom_args}
fi

# Create GPU Dashboard config map
if ! kubectl -n monitoring get configmap kube-prometheus-grafana-gpu >/dev/null 2>&1 ; then
    kubectl create configmap kube-prometheus-grafana-gpu --from-file=${config_dir}/gpu-dashboard.json -n monitoring
    kubectl -n monitoring label configmap kube-prometheus-grafana-gpu grafana_dashboard=1
fi

# Label GPU nodes
for node in $(kubectl get node --no-headers -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com\\/gpu | grep -v none | awk '{print $1}') ; do
    kubectl label nodes ${node} hardware-type=NVIDIAGPU --overwrite >/dev/null
done

# Deploy DCGM node exporter
if kubectl -n monitoring get pod -l app=dcgm-exporter 2>&1 | grep "No resources found." >/dev/null 2>&1 ; then
    if [ "${DCGM_DOCKER_REGISTRY}" ]; then
        cat services/dcgm-exporter.yml \
        | sed "s/image: quay.io/image: ${DCGM_DOCKER_REGISTRY}/g" \
        | sed "s/image: nvcr.io/image: ${DCGM_DOCKER_REGISTRY}/g" \
        | kubectl create -f -
    else
        kubectl create -f services/dcgm-exporter.yml
    fi
fi

# Get Grafana auth details
grafana_user=$(kubectl -n monitoring get secrets prometheus-operator-grafana -o 'go-template={{ index .data "admin-user" }}' | base64 -d)
grafana_password=$(kubectl -n monitoring get secrets prometheus-operator-grafana -o 'go-template={{ index .data "admin-password" }}' | base64 -d)

# Use NodePort directly if the IP string uses the master IP, otherwise use Ingress URL
if echo "${ingress_ip_string}" | grep "${master_ip}" >/dev/null 2>&1; then
    grafana_port=$(kubectl -n monitoring get svc prometheus-operator-grafana --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
    prometheus_port=$(kubectl -n monitoring get svc prometheus-operator-prometheus --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
    alertmanager_port=$(kubectl -n monitoring get svc prometheus-operator-alertmanager --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)

    export grafana_url="http://${master_ip}:${grafana_port}/"
    export prometheus_url="http://${master_ip}:${prometheus_port}/"
    export alertmanager_url="http://${master_ip}:${alertmanager_port}/"
else
    export grafana_url="http://grafana-${ingress_ip_string}/"
    export prometheus_url="http://prometheus-${ingress_ip_string}/"
    export alertmanager_url="http://alertmanager-${ingress_ip_string}/"
fi

echo
echo "Grafana: ${grafana_url}     admin user: ${grafana_user}     admin password: ${grafana_password}"
echo "Prometheus: ${prometheus_url}"
echo "Alertmanager: ${alertmanager_url}"
