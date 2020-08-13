#!/bin/bash
set -e
source .jenkins-scripts/jenkins-common.sh

# Install Spack, but do not install any modules
ansible-playbook -i virtual/config/inventory playbooks/spack-modules.sh

# After install, we expect spack to be in our PATH
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	"which spack"
