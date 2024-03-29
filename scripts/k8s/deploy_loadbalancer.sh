#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Source common libraries and env variables
source ${ROOT_DIR}/scripts/common.sh

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

# Add Helm metallb repo if it doesn't exist
HELM_CHARTS_REPO_METALLB="${HELM_CHARTS_REPO_METALLB:-https://metallb.github.io/metallb}"
HELM_METALLB_CHART_VERSION=${HELM_METALLB_CHART_VERSION:-0.13.9}
if ! helm repo list | grep metallb  >/dev/null 2>&1 ; then
	helm repo add metallb "${HELM_CHARTS_REPO_METALLB}"
	helm repo update
fi

# We need to dynamically set up Helm args, so let's use an array
helm_install_args=("--values" "${DEEPOPS_CONFIG_DIR}/helm/metallb.yml")
if [ "${METALLB_SPEAKER_REPO}" ]; then
	helm_install_args+=("--set-string" "speaker.image.repository=${METALLB_SPEAKER_REPO}")
fi
if [ "${METALLB_CONTROLLER_REPO}" ]; then
	helm_install_args+=("--set-string" "controller.image.repository=${METALLB_CONTROLLER_REPO}")
fi

# Set up the MetalLB load balancer
if ! helm status metallb -n deepops-loadbalancer >/dev/null 2>&1; then
	kubectl create namespace deepops-loadbalancer
	kubectl label namespace deepops-loadbalancer pod-security.kubernetes.io/enforce=privileged
	kubectl label namespace deepops-loadbalancer pod-security.kubernetes.io/audit=privileged
	kubectl label namespace deepops-loadbalancer pod-security.kubernetes.io/warn=privileged
	helm install --wait metallb metallb/metallb "${helm_install_args[@]}" --version ${HELM_METALLB_CHART_VERSION} --namespace deepops-loadbalancer
	kubectl create -n deepops-loadbalancer -f "${DEEPOPS_CONFIG_DIR}/helm/metallb-resources.yml"
fi
