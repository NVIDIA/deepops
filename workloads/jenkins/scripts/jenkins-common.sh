#!/bin/bash
pwd

# This is a common library sourced at the top of all Jenkins scripts.
#
# Everything passed into Jenkins has the "GPUDATA" environment variable set.
# This variable will either indicate that 1 or 2 GPUs have been locked and allocated.
# For a single GPU GPUDATA will look like: "3-0x86"
# For two GPUs GPUDATA will look like:     "3-0x86,2-0x85"
#
# Additionally, the "DEEPOPS_FULL_INSTALL" flag may be set.
# This flag should be set if 2 GPUs are allocated
# If this flag is blank or not set, everything involving GPU01, MGMT02, and MGMT03 will be ignored.
# If this flag is set to true, we will calculate the IPs and other information for these nodes.
#
# This information is later used to grep & sed files, and to ssh to/access the cluster.

# Verify the GPUDATA variable is set by Jenkins
if [ -z "${GPUDATA+x}" ]; then
        echo "GPUDATA variable is not set, are we running in Jenkins?"
        echo "Bailing!"
        exit 1
fi

# No-op if DEEPOPS_FULL_INSTALL is not set, this is here for debug
export DEEPOPS_FULL_INSTALL=${DEEPOPS_FULL_INSTALL:-}

# Get BUS values of GPU01
GPU01="$(echo "${GPUDATA}" | cut -d"," -f1 | cut -d"-" -f1)"
export GPU01
BUS01="$(echo "${GPUDATA}" | cut -d"," -f1 | cut -d"-" -f2)"
export BUS01

# Get BUS values of GPU02
if [ ${DEEPOPS_FULL_INSTALL} ]; then
  GPU02="$(echo "${GPUDATA}" | cut -d"," -f2 | cut -d"-" -f1)"
  export GPU02
  BUS02="$(echo "${GPUDATA}" | cut -d"," -f2 | cut -d"-" -f2)"
  export BUS02
fi

# Get absolute path for the virtual DeepOps directory
export VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/../../../virtual"
export ROOT_DIR="${VIRT_DIR}/.."

# Set variables used for kubectl
K8S_CONFIG_DIR=${VIRT_DIR}/config
export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"

# Let setup script know we're running from a Jenkins job
export JENKINS=1
