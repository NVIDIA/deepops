#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

set -ex

# Ensure working directory is root
cd "${ROOT_DIR}" || exit 1

# Deploy a Deep Learning Example
JENKINS_DLE="${JENKINS_DLE:-pytorch-detection-ssd}"
JENKINS_DLE_NODEPORT="30888"

if ! which helm; then
	echo "helm command not available"
	exit 1
fi

helm install \
	--wait \
	--timeout 1200s \
	"${JENKINS_DLE}" \
	workloads/examples/k8s/deep-learning-examples \
	--set exampleName="${JENKINS_DLE}"

if [ $? -ne 0 ]; then
	echo "Failed to deploy DLE"
	exit 1
fi

sleep 60

# Test that we can ping the endpoint
if ! curl http://10.0.0.2${GPU01}:${JENKINS_DLE_NODEPORT}/ 2>&1 >/dev/null ; then
	echo "Failed to ping Jupyter notebook"
	exit 1
fi

# Remove the DLE
if ! helm uninstall "${JENKINS_DLE}"; then
	echo "Failed to uninstall DLE"
	exit 1
fi
