#!/usr/bin/env bash

rook_tools_pod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o name | cut -d \/ -f2 | sed -e 's/\\r$//g')

while true; do
    kubectl -n rook-ceph exec -ti $rook_tools_pod ceph status # Run once to print output
    kubectl -n rook-ceph exec -ti $rook_tools_pod ceph status | grep "mds: cephfs" | grep "up:active" | grep "standby-replay" # Run again to check for completion
    if [ "${?}" == "0" ]; then
    	echo "Ceph has completed setup."
        break
    fi
    sleep 15
done
