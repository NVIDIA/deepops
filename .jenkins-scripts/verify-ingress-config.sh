#!/bin/bash
source jenkins-common.sh

pwd
cd virtual || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"
nginx_external_ip=$(kubectl get services -l app=nginx-ingress,component=controller --no-headers | awk '{print $4}')
curl "http://${nginx_external_ip}/" 
