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
	return 1
fi

# Set the Docker registry location
export DEEPOPS_DOCKER_REGISTRY="${DEEPOPS_DOCKER_REGISTRY:-fake-ip-address}"
if echo "${DEEPOPS_DOCKER_REGISTRY}" | grep "fake-ip-address" >/dev/null 2>&1; then
	echo "You need to set DEEPOPS_DOCKER_REGISTRY to point to your Docker registry"
	return 1
fi

# Set the Helm chart location
export DEEPOPS_HELM_REPO="${DEEPOPS_HELM_REPO:-fake}"
if echo "${DEEPOPS_HELM_REPO}" | grep "fake" >/dev/null 2>&1; then
	echo "You need to set DEEPOPS_HELM_REPO to point to the Helm charts repo"
	return 1
fi

# Set env vars used by DeepOps deployment scripts
export DOCKER_COMPOSE_URL="${DEEPOPS_MISC_MIRROR}/docker-compose"
export HELM_INSTALL_SCRIPT_URL="${DEEPOPS_MISC_MIRROR}/helm-v2.11.0-linux-amd64.tar.gz"
export KSONNET_URL="${DEEPOPS_MISC_MIRROR}/ks_0.13.1_linux_amd64.tar.gz"
export KUBECTL_BINARY_URL="${DEEPOPS_MISC_MIRROR}/kubectl"

# Rook/Ceph
export HELM_ROOK_CHART_REPO="${DEEPOPS_HELM_REPO}"
export ROOK_CEPH_IMAGE_REPO="${DEEPOPS_DOCKER_REGISTRY}/rook/ceph"
export DEEPOPS_ROOK_DOCKER_REGISTRY="${DEEPOPS_DOCKER_REGISTRY}"

# MetalLB
export METALLB_SPEAKER_REPO="${DEEPOPS_DOCKER_REGISTRY}/metallb/speaker"
export METALLB_CONTROLLER_REPO="${DEEPOPS_DOCKER_REGISTRY}/metallb/controller"

# NGINX ingress
export NGINX_INGRESS_CONTROLLER_REPO="${DEEPOPS_DOCKER_REGISTRY}/kubernetes-ingress-controller/nginx-ingress-controller"
export NGINX_INGRESS_BACKEND_REPO="${DEEPOPS_DOCKER_REGISTRY}/defaultbackend"

# Monitoring
export HELM_COREOS_CHART_REPO="${DEEPOPS_HELM_REPO}"
export PROMETHEUS_OPER_REPO="${DEEPOPS_DOCKER_REGISTRY}/coreos/prometheus-operator"
export ALERTMANAGER_REPO="${DEEPOPS_DOCKER_REGISTRY}/prometheus/alertmanager"
export PROMETHEUS_REPO="${DEEPOPS_DOCKER_REGISTRY}/prometheus/prometheus"
export GRAFANA_WATCHER_REPO="${DEEPOPS_DOCKER_REGISTRY}/coreos/grafana-watcher"
export GRAFANA_REPO="${DEEPOPS_DOCKER_REGISTRY}/grafana/grafana"
export DCGM_DOCKER_REGISTRY="${DEEPOPS_DOCKER_REGISTRY}"
