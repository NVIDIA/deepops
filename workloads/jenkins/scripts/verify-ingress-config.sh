#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"

master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# TODO: Come up with a better kubectl command here instead of a grep -v, currently two services have the same Selector
ingress_port=$(kubectl get services --no-headers -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller  -o custom-columns=PORT:.spec.ports.*.nodePort | grep -v none | awk -F, '{print $1}')

url="http://${master_ip}:${ingress_port}"
curl ${url}
