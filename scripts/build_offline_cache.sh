#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
DEEPOPS_CONFIG_DIR="${DEEPOPS_CONFIG_DIR:-${ROOT_DIR}/config.example}"

echo "Building an offline cache of DeepOps dependencies on the local host"

cd "${ROOT_DIR}" || exit 1
ansible-playbook -i "${DEEPOPS_CONFIG_DIR}/offline_cache/localhost_inventory" playbooks/build-offline-cache.yml
