#!/bin/bash

kubectl delete -f workloads/services/k8s/rook-cluster.yml
helm delete rook-ceph
kubectl -n rook-ceph delete cephcluster rook-ceph
kubectl -n rook-ceph delete storageclass rook-ceph-block
kubectl delete ns rook-ceph-system
kubectl delete ns rook-ceph
ansible k8s-cluster -b -m file -a "path=/var/lib/rook state=absent"
