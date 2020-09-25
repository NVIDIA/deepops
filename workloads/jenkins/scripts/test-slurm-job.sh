#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun -n1 hostname
