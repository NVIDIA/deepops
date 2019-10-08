#!/bin/bash

pwd
cd virtual || exit 1

K8S_CONFIG_DIR="$(pwd)/config"
export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"
nginx_external_ip=$(kubectl get services -l app=nginx-ingress,component=controller --no-headers | awk '{print $4}')
curl "http://${nginx_external_ip}/" 
