#!/bin/bash
pwd

if [ -z "${GPUDATA+x}" ]; then
        echo "GPUDATA variable is not set, are we running in Jenkins?"
        echo "Bailing!"
        exit 1
fi

GPU01="$(echo "${GPUDATA}" | cut -d"," -f1 | cut -d"-" -f1)"
export GPU01
BUS01="$(echo "${GPUDATA}" | cut -d"," -f1 | cut -d"-" -f2)"
export BUS01
GPU02="$(echo "${GPUDATA}" | cut -d"," -f2 | cut -d"-" -f1)"
export GPU02
BUS02="$(echo "${GPUDATA}" | cut -d"," -f2 | cut -d"-" -f2)"
export BUS02

# Get absolute path for the virtual DeepOps directory
export VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../virtual"
export ROOT_DIR="${VIRT_DIR}/.."

K8S_CONFIG_DIR=${VIRT_DIR}/config
export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"
