#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

HELM_CHARTS_REPO_INGRESS="${HELM_CHARTS_REPO_INGRESS:-https://kubernetes.github.io/ingress-nginx}"
HELM_INGRESS_CHART_VERSION="${HELM_INGRESS_CHART_VERSION:-3.5.1}"
# HELM_INGRESS_CONFIG, defaults below based on presence of metallb

${SCRIPT_DIR}/install_helm.sh

# Allow overriding the app name with an env var
app_name="${NGINX_INGRESS_APP_NAME:-ingress-nginx}"

# Allow overriding config dir to look in
DEEPOPS_CONFIG_DIR=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}

if [ ! -d "${DEEPOPS_CONFIG_DIR}" ]; then
	echo "Can't find configuration in ${DEEPOPS_CONFIG_DIR}"
	echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
	exit 1
fi

if ! kubectl version ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# If MetalLB is installed, use LoadBalancer, otherwise use NodePort (unless the user specifies a config)
if ! helm status metallb -n deepops-loadbalancer >/dev/null 2>&1; then
	HELM_INGRESS_CONFIG="${HELM_INGRESS_CONFIG:-${ROOT_DIR}/workloads/examples/k8s/ingress-nodeport.yml}"
else
	HELM_INGRESS_CONFIG="${HELM_INGRESS_CONFIG:-${ROOT_DIR}/workloads/examples/k8s/ingress-loadbalancer.yml}"
fi

# We need to dynamically set up Helm args, so let's use an array
helm_arguments=("--version" "${HELM_INGRESS_CHART_VERSION}"
		"--values" "${HELM_INGRESS_CONFIG}"
)

if [ "${NGINX_INGRESS_CONTROLLER_REPO}" ]; then
	helm_arguments+=("--set-string" "controller.image.repository=${NGINX_INGRESS_CONTROLLER_REPO}")
fi
if [ "${NGINX_INGRESS_BACKEND_REPO}" ]; then
	helm_arguments+=("--set-string" "defaultBackend.image.repository=${NGINX_INGRESS_BACKEND_REPO}")
fi

# Add Helm ingress-nginx repo if it doesn't exist
if ! helm repo list | grep ingress-nginx >/dev/null 2>&1 ; then
	helm repo add ingress-nginx "${HELM_CHARTS_REPO_INGRESS}"
fi

# Set up the ingress controller
if ! helm status "${app_name}" >/dev/null 2>&1; then
	helm repo update
	helm install --wait "${app_name}" "${helm_arguments[@]}" ingress-nginx/ingress-nginx --create-namespace --namespace deepops-ingress
fi
