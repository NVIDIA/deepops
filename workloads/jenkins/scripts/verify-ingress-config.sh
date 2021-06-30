#!/bin/bash

source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

master_ip=$(kubectl get endpoints ingress-nginx-controller --no-headers -n deepops-ingress -o custom-columns=ENDPOINTS:.subsets[0].addresses[0].ip)

# TODO: Come up with a better kubectl command here instead of a grep -v and head -n1, currently two services have the same Selector
ingress_port=$(kubectl get services -A --no-headers -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller  -o custom-columns=PORT:.spec.ports.*.nodePort | grep -v none | awk -F, '{print $1}')
ingress_https_port=$(kubectl get services -A --no-headers -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller  -o custom-columns=PORT:.spec.ports.*.nodePort | grep -v none | awk -F, '{print $2}')

# Test http
curl "http://${master_ip}"
curl "http://${master_ip}:${ingress_port}"

# Test https
curl -k "https://${master_ip}"
curl -k "https://${master_ip}:${ingress_https_port}"

