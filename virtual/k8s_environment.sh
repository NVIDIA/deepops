#!/bin/bash
#
# Set up local environment to work with virtual k8s cluster

K8S_CONFIG_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/config"

export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"
