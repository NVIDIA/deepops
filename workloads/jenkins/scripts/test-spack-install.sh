#!/bin/bash
set -e
source workloads/jenkins/scripts/jenkins-common.sh

# Install Spack, including building default modules
ansible-playbook \
	-i virtual/config/inventory \
	-e '{"spack_build_packages": true}' \
	playbooks/slurm-cluster/spack-modules.yml

# After install, we expect a cuda module to exist
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	"spack find | grep cuda"
