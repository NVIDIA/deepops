#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Upload test script
scp  \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-i "${HOME}/.ssh/id_rsa" \
	workloads/jenkins/scripts/remote-script-for-slurm-gpu.sh \
	"vagrant@10.0.0.5${GPU01}:remote-script-for-slurm-gpu.sh"

# Compile and run CUDA sample 
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	"bash -l /home/vagrant/remote-script-for-slurm-gpu.sh"
