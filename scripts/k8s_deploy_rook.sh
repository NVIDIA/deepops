#!/usr/bin/env bash

type helm >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    ./scripts/install_helm.sh
fi

helm repo list | grep rook-master >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    helm repo add rook-master https://charts.rook.io/master
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

echo
echo "Ceph deployed, it may take up to 10 minutes for storage to be ready"
echo "Monitor readiness with:"
echo "kubectl -n rook-ceph exec -ti ${toolspod} ceph status | grep up:active"
echo
