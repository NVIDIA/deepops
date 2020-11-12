#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Check that we have installed a local registry on the cluster,
# and that we are configured to use it as a mirror.

set -ex

# Check that deepops-registry container is running
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.2${GPU01}" \
	"sudo docker ps | grep deepops-registry"

# Check that dockerd is configured to use this registry as a mirror
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.2${GPU01}" \
	"ps auxw | grep dockerd | grep 'insecure-registry=virtual-mgmt'"
