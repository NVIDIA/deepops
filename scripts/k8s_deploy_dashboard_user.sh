#!/usr/bin/env bash

# Make the dashboard a NodePort
kubectl patch svc -n kube-system kubernetes-dashboard  -p '{"spec": {"type": "NodePort", "ports": [{"nodePort": 31443, "port": 443}] }}'

kubectl -n kube-system get sa admin-user 2>&1 | grep "NotFound" >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    kubectl apply -f services/k8s-dashboard-admin.yml
fi

# Get IP of first master
dashboard_port=$(kubectl -n kube-system get svc kubernetes-dashboard --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# Get access token
token=$(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') | grep ^token: | awk '{print $2}')

export dashboard_url="https://${master_ip}:${dashboard_port}"

# Print Dashboard address
echo
echo "Dashboard is available at: ${dashboard_url}"

# Print token
echo
echo "Access token: ${token}"
echo
