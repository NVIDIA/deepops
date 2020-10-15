#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"
nginx_external_ip=$(kubectl get services -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller --no-headers | grep -v admission | awk '{print $4}') # TODO: Come up with a better kubectl command here instead of a grep -v, currently two services have the same Selector
curl "http://${nginx_external_ip}/" 
