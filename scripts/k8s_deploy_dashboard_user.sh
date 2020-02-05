#!/usr/bin/env bash

kubectl -n kube-system get sa admin-user 2>&1 | grep "NotFound" >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    kubectl apply -f services/k8s-dashboard-admin.yml
fi

# Get IP of first master
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# Get access token
token=$(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') | grep ^token: | awk '{print $2}')

export dashboard_url="https://${master_ip}:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"
# Print Dashboard address
echo
echo "Dashboard is available at: ${dashboard_url}"

# Print token
echo
echo "Access token: ${token}"
echo
