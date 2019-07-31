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

kubectl version
if [ $? -ne 0 ] ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# Check for environment vars overriding image names
helm_extra_args=""
if [ "${METALLB_SPEAKER_REPO}" ]; then
	helm_extra_args="${helm_extra_args} --set-string speaker.image.repository="${METALLB_SPEAKER_REPO}""
fi
if [ "${METALLB_CONTROLLER_REPO}" ]; then
	helm_extra_args="${helm_extra_args} --set-string controller.image.repository="${METALLB_CONTROLLER_REPO}""
fi

# Set up the MetalLB load balancer
if ! helm status metallb >/dev/null 2>&1; then
	helm install \
		--values "${config_dir}/helm/metallb.yml"  ${helm_extra_args} \
		--name metallb \
		stable/metallb
fi

kubectl wait --for=condition=Ready -l app=metallb,component=controller pod
