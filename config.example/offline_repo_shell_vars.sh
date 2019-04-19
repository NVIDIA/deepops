#!/bin/bash
#
# Several DeepOps deployment scripts download files from the Internet, with the
# URLs set using environment variables.
# This script sets the relevant environment variables so that these scripts can
# use a local mirror.

# Set a variable that DeepOps is being built offline, so that other scripts
# can modify their behavior as needed.
export DEEPOPS_OFFLINE=1

# Set the mirror server location
export DEEPOPS_MISC_MIRROR="${DEEPOPS_MISC_MIRROR:-fake-ip-address}"
if echo "${DEEPOPS_MISC_MIRROR}" | grep "fake-ip-address" >/dev/null 2>&1; then
	echo "You need to set DEEPOPS_MISC_MIRROR to point to the mirror host"
	exit 1
fi

# Set env vars used by DeepOps deployment scripts
export DOCKER_COMPOSE_URL="${DEEPOPS_MISC_MIRROR}/docker-compose"
export HELM_INSTALL_SCRIPT_URL="${DEEPOPS_MISC_MIRROR}/helm-v2.11.0-linux-amd64.tar.gz"
export KSONNET_URL="${DEEPOPS_MISC_MIRROR}/ks_0.13.1_linux_amd64.tar.gz"
export KUBECTL_BINARY_URL="${DEEPOPS_MISC_MIRROR}/kubectl"
