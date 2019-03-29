#!/usr/bin/env bash

# Upgrading:
# `helm update`
# `helm search rook` # get latest version number
# `helm upgrade --namespace rook-ceph-system rook-ceph rook-master/rook-ceph --version v0.9.0-174.g3b14e51`

HELM_ROOK_CHART_REPO="${HELM_ROOK_CHART_REPO:-https://charts.rook.io/master}"

type helm >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    ./scripts/install_helm.sh
fi

helm repo list | grep rook-master >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm repo add rook-master "${HELM_ROOK_CHART_REPO}"
fi

helm status rook-ceph >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm install --namespace rook-ceph-system --name rook-ceph rook-master/rook-ceph --version v0.9.0-79.g1a1ffdd
fi

kubectl -n rook-ceph get pod -l app=rook-ceph-tools 2>&1 | grep "No resources found." >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    sleep 5
    kubectl create -f services/rook-cluster.yml
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
echo "Monitor readiness with:"
echo "kubectl -n rook-ceph exec -ti ${toolspod} ceph status | grep up:active"
echo

echo "Ceph dashboard: https://${master_ip}:${dash_port}"
echo
echo "Create dashboard user with: kubectl -n rook-ceph exec -ti ${toolspod} ceph dashboard set-login-credentials <username> <password>"
echo
