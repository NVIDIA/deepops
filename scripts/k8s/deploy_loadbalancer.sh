#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

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

# Add Helm stable repo if it doesn't exist
HELM_CHARTS_REPO_STABLE="${HELM_CHARTS_REPO_STABLE:-https://kubernetes-charts.storage.googleapis.com}"
if ! helm repo list | grep stable >/dev/null 2>&1 ; then
    helm repo add stable "${HELM_CHARTS_REPO_STABLE}"
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
if ! helm status metallb >/dev/null 2>&1; then
	helm install metallb stable/metallb "${helm_install_args[@]}"
fi

kubectl wait --timeout=120s --for=condition=Ready -l app=metallb,component=controller pod
