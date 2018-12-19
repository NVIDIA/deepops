#!/usr/bin/env bash

HELM_INSTALL_DIR=~/.local/bin

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > /tmp/get_helm.sh
chmod +x /tmp/get_helm.sh
sed -i 's/sudo//g' /tmp/get_helm.sh
mkdir -p ${HELM_INSTALL_DIR}
HELM_INSTALL_DIR=${HELM_INSTALL_DIR} DESIRED_VERSION=v2.9.1 /tmp/get_helm.sh

echo Add ${HELM_INSTALL_DIR} to your PATH

helm init
