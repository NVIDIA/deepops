#!/usr/bin/env bash
# See https://rook.io/docs/rook/v1.1/ceph-quickstart.html
echo "Beginning to poll for Ceph and Rook setup completion."
echo "This may throw several errors and take up to 10 minutes. This behavior is expected."
echo "The script will polling when Ceph setup is completed and in a healthy state".

while true; do
    rook_tools_pod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o name | cut -d \/ -f2 | sed -e 's/\\r$//g')
    kubectl -n rook-ceph exec -ti $rook_tools_pod ceph status # Run once to print output
    kubectl -n rook-ceph exec -ti $rook_tools_pod ceph status | grep "mds: cephfs" | grep "up:active" | grep "standby-replay" # Run again to check for completion
    if [ "${?}" == "0" ]; then
    	echo "Ceph has completed setup."
        break
    fi
    sleep 15
done
