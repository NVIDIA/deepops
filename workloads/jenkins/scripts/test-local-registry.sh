#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

set -ex

# Ensure working directory is root
cd "${ROOT_DIR}" || exit 1

# Wait for Docker registry to be online
kubectl wait --for=condition=ready --timeout=600s pod -l app=docker-registry

# Upload script for pushing image to registry
scp  \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-i "${HOME}/.ssh/id_rsa" \
	workloads/jenkins/scripts/remote-script-for-registry-test.sh \
	"vagrant@10.0.0.2${GPU01}:remote-script-for-registry-test.sh"

# Run the remote script
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.2${GPU01}" \
	"bash -l /home/vagrant/remote-script-for-registry-test.sh"

# Deploy a pod based on the image we pushed
kubectl apply -f workloads/jenkins/scripts/files/nginx-from-local-registry.yml

# Wait for the pod to be ready
kubectl wait --for=condition=ready --timeout=300s pod/nginx-registry-local
