#!/bin/bash

dops() {
    ./deepops "$@"
}

dops kubectl delete -f services/rook-cluster.yml
dops helm del --purge rook-ceph
dops kubectl -n rook-ceph delete cephcluster rook-ceph
dops kubectl -n rook-ceph delete storageclass rook-ceph-block
dops kubectl delete ns rook-ceph-system
dops kubectl delete ns rook-ceph
dops ansible management -b -m file -a "path=/var/lib/rook state=absent"
