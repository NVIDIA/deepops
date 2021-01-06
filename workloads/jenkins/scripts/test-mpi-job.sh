#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Upload MPI source
scp  \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-i "${HOME}/.ssh/id_rsa" \
	workloads/examples/slurm/mpi-hello/mpi-hello.c \
	"vagrant@10.0.0.5${GPU01}:mpi-hello.c"

# Upload test script
scp  \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-i "${HOME}/.ssh/id_rsa" \
	workloads/jenkins/scripts/remote-script-for-mpi.sh \
	"vagrant@10.0.0.5${GPU01}:remote-script-for-mpi.sh"

# Compile the program
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	"bash -l /home/vagrant/remote-script-for-mpi.sh"
