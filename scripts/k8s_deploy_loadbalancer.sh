#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."

# Allow overriding config dir to look in
config_dir=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}
if [ ! -d "${config_dir}" ]; then
	echo "Can't find configuration in ${config_dir}"
	echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
	exit 1
fi

if ! kubectl version ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# We need to dynamically set up Helm args, so let's use an array
helm_install_args=("--values" "${config_dir}/helm/metallb.yml"
                   "--name" "metallb"
)
if [ "${METALLB_SPEAKER_REPO}" ]; then
	helm_install_args+=("--set-string" "speaker.image.repository=${METALLB_SPEAKER_REPO}")
fi
if [ "${METALLB_CONTROLLER_REPO}" ]; then
	helm_install_args+=("--set-string" "controller.image.repository=${METALLB_CONTROLLER_REPO}")
fi

# Set up the MetalLB load balancer
if ! helm status metallb >/dev/null 2>&1; then
	helm install "${helm_install_args[@]}" stable/metallb
fi

kubectl wait --for=condition=Ready -l app=metallb,component=controller pod
