#!/usr/bin/env bash

# Optional log search for Kubernetes: Loki (single binary, persistent volume)
# plus Grafana Alloy on every node, with Loki added as a source in the Grafana
# installed by scripts/k8s/deploy_monitoring.sh. Off by default: nothing runs
# unless you run this script.

# Ensure we start in the correct working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
cd "${ROOT_DIR}" || exit 1

source "${ROOT_DIR}/scripts/common.sh"

DEEPOPS_CONFIG_DIR=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}

# Loki's free chart is community-maintained (grafana-community) since 2026-03.
HELM_CHARTS_REPO_LOKI="${HELM_CHARTS_REPO_LOKI:-https://grafana-community.github.io/helm-charts}"
HELM_LOKI_CHART_VERSION="${HELM_LOKI_CHART_VERSION:-21.2.3}"
HELM_CHARTS_REPO_ALLOY="${HELM_CHARTS_REPO_ALLOY:-https://grafana.github.io/helm-charts}"
HELM_ALLOY_CHART_VERSION="${HELM_ALLOY_CHART_VERSION:-1.16.0}"

LOKI_YAML_CONFIG="${LOKI_YAML_CONFIG:-${DEEPOPS_CONFIG_DIR}/helm/loki.yml}"
ALLOY_YAML_CONFIG="${ALLOY_YAML_CONFIG:-${DEEPOPS_CONFIG_DIR}/helm/alloy.yml}"
LOGGING_NAMESPACE="${LOGGING_NAMESPACE:-monitoring}"
GRAFANA_LOKI_DATASOURCE_CM="grafana-loki-datasource"
GRAFANA_LOGS_DASHBOARD_CM="kube-prometheus-grafana-logs"

function help_me() {
    echo "This script installs optional log search: Loki, Alloy and a Grafana data source."
    echo "Run scripts/k8s/deploy_monitoring.sh first (Grafana must exist in the '${LOGGING_NAMESPACE}' namespace)."
    echo ""
    echo "Usage:"
    echo "-h      This message."
    echo "-d      Uninstall Loki, Alloy and the Grafana additions. Pass -D as well to delete stored logs."
    echo "-D      With -d, also delete the Loki persistent volume claim (stored logs)."
    echo "-t      Render the charts locally (helm template) without touching the cluster."
}

DELETE=""
DELETE_DATA=""
TEMPLATE_ONLY=""
while getopts "hdDt" option; do
    case $option in
        d) DELETE=1 ;;
        D) DELETE_DATA=1 ;;
        t) TEMPLATE_ONLY=1 ;;
        *) help_me; exit 1 ;;
    esac
done

function add_repos() {
    helm repo add grafana-community "${HELM_CHARTS_REPO_LOKI}" >/dev/null 2>&1 || true
    helm repo add grafana "${HELM_CHARTS_REPO_ALLOY}" >/dev/null 2>&1 || true
    helm repo update grafana-community grafana >/dev/null
}

function render_only() {
    add_repos || exit 1
    helm template loki grafana-community/loki --version "${HELM_LOKI_CHART_VERSION}" \
        --namespace "${LOGGING_NAMESPACE}" --values "${LOKI_YAML_CONFIG}" >/dev/null || exit 1
    helm template alloy grafana/alloy --version "${HELM_ALLOY_CHART_VERSION}" \
        --namespace "${LOGGING_NAMESPACE}" --values "${ALLOY_YAML_CONFIG}" >/dev/null || exit 1
    echo "Loki ${HELM_LOKI_CHART_VERSION} and Alloy ${HELM_ALLOY_CHART_VERSION} charts render OK"
}

function delete_logging() {
    helm uninstall alloy -n "${LOGGING_NAMESPACE}"
    helm uninstall loki -n "${LOGGING_NAMESPACE}"
    kubectl -n "${LOGGING_NAMESPACE}" delete configmap "${GRAFANA_LOKI_DATASOURCE_CM}" "${GRAFANA_LOGS_DASHBOARD_CM}" --ignore-not-found
    if [ "${DELETE_DATA}" ]; then
        kubectl -n "${LOGGING_NAMESPACE}" delete pvc -l app.kubernetes.io/instance=loki
    else
        echo "Stored logs kept (PVC). Re-run with -d -D to delete them."
    fi
}

function install_logging() {
    kubectl version >/dev/null 2>&1 || { echo "Unable to talk to Kubernetes API"; exit 1; }
    ./scripts/k8s/install_helm.sh
    if ! kubectl get ns "${LOGGING_NAMESPACE}" >/dev/null 2>&1; then
        echo "Namespace ${LOGGING_NAMESPACE} not found. Run scripts/k8s/deploy_monitoring.sh first." >&2
        exit 1
    fi
    kubectl get storageclass 2>&1 | grep "(default)" >/dev/null 2>&1 || {
        echo "No default StorageClass found; Loki needs a persistent volume." >&2
        exit 1
    }
    add_repos || exit 1

    helm upgrade --install loki grafana-community/loki --version "${HELM_LOKI_CHART_VERSION}" \
        --namespace "${LOGGING_NAMESPACE}" --values "${LOKI_YAML_CONFIG}" --timeout 600s --wait || exit 1
    helm upgrade --install alloy grafana/alloy --version "${HELM_ALLOY_CHART_VERSION}" \
        --namespace "${LOGGING_NAMESPACE}" --values "${ALLOY_YAML_CONFIG}" --timeout 600s --wait || exit 1

    # Grafana's sidecar picks up labelled ConfigMaps (datasource + dashboard).
    kubectl -n "${LOGGING_NAMESPACE}" create configmap "${GRAFANA_LOKI_DATASOURCE_CM}" \
        --from-file=loki-datasource.yaml="${DEEPOPS_CONFIG_DIR}/helm/loki-datasource.yaml" \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "${LOGGING_NAMESPACE}" label configmap "${GRAFANA_LOKI_DATASOURCE_CM}" grafana_datasource=1 --overwrite
    kubectl -n "${LOGGING_NAMESPACE}" create configmap "${GRAFANA_LOGS_DASHBOARD_CM}" \
        --from-file="${ROOT_DIR}/src/dashboards/cluster-logs-dashboard.json" \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "${LOGGING_NAMESPACE}" label configmap "${GRAFANA_LOGS_DASHBOARD_CM}" grafana_dashboard=1 --overwrite
    echo "Log search installed. Open Grafana > Dashboards > Cluster logs (or Explore > Loki)."
}

if [ "${TEMPLATE_ONLY}" ]; then render_only; exit $?; fi
if [ "${DELETE}" ]; then delete_logging; exit 0; fi
install_logging
