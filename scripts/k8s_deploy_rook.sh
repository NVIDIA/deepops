#!/usr/bin/env bash

# Upgrading:
# `helm update`
# `helm search rook` # get latest version number
# `helm upgrade --namespace rook-ceph rook-ceph rook-release/rook-ceph --version v0.9.0-174.g3b14e51`

HELM_ROOK_CHART_REPO="${HELM_ROOK_CHART_REPO:-https://charts.rook.io/release}"
HELM_ROOK_CHART_VERSION="${HELM_ROOK_CHART_VERSION:-v1.1.1}"

./scripts/install_helm.sh

if ! kubectl get ns rook-ceph >/dev/null 2>&1 ; then
    kubectl create ns rook-ceph
fi

# https://github.com/rook/rook/blob/master/Documentation/helm-operator.md
helm repo add rook-release "${HELM_ROOK_CHART_REPO}"

# We need to dynamically set up Helm args, so let's use an array
helm_install_args=("--namespace" "rook-ceph"
		   "--version" "${HELM_ROOK_CHART_VERSION}"
)

# Use an alternate image if set
if [ "${ROOK_CEPH_IMAGE_REPO}" ]; then
	helm_install_args+=("--set" "image.repository=${ROOK_CEPH_IMAGE_REPO}")
fi

# Install rook-ceph
if ! helm status -n rook-ceph rook-ceph >/dev/null 2>&1 ; then
    helm install rook-ceph rook-release/rook-ceph "${helm_install_args[@]}"
fi

if kubectl -n rook-ceph get pod -l app=rook-ceph-tools 2>&1 | grep "No resources found." >/dev/null 2>&1; then
    sleep 5
    # If we have an alternate registry defined, dynamically substitute it in
    if [ "${DEEPOPS_ROOK_DOCKER_REGISTRY}" ]; then
        sed "s/image: /image: ${DEEPOPS_ROOK_DOCKER_REGISTRY}\//g" services/rook-cluster.yml | kubectl create -f -
    else
        kubectl create -f services/rook-cluster.yml
    fi
fi

sleep 5

# Get Rook Ceph Tools POD name
toolspod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools --no-headers -o custom-columns=:.metadata.name)

# Get IP of first master
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# Get Ceph dashboard port
dash_port=$(kubectl -n rook-ceph get svc rook-ceph-mgr-dashboard-external-https --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)

echo
echo "Ceph deployed, it may take up to 10 minutes for storage to be ready"
echo "If install takes more than 30 minutes be sure you have cleaned up any previous Rook installs using the rmrook.sh script and have installed the required libraries using the bootstrap-rook.yml playbook"
echo "Monitor readiness with:"
echo "kubectl -n rook-ceph exec -ti ${toolspod} ceph status | grep up:active"
echo

echo "Ceph dashboard: https://${master_ip}:${dash_port}"
echo
echo "Create dashboard user with: kubectl -n rook-ceph exec -ti ${toolspod} ceph dashboard set-login-credentials <username> <password>"
echo
