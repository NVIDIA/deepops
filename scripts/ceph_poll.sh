#!/usr/bin/env bash

while true; do
    kubectl -n rook-ceph exec -ti rook-ceph-tools ceph status # Run once to print output
    kubectl -n rook-ceph exec -ti rook-ceph-tools ceph status | grep "mds: cephfs" | grep "up:active" | grep "standby-replay" # Run again to check for completion
    if [ "${?}" == "0" ]; then
    	echo "Ceph has completed setup."
        break
    fi
    sleep 15
done
