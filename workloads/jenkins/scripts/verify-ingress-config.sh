#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"
nginx_external_ip=$(kubectl get services -l app.kubernetes.io/name=nginx-ingress,app.kubernetes.io/component=controller --no-headers | awk '{print $4}' | grep -v none)
curl "http://${nginx_external_ip}/" 
