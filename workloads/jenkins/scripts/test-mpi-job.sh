#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Upload MPI source
scp  \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-i "${HOME}/.ssh/id_rsa" \
	workloads/examples/slurm/mpi-hello/mpi-hello.c \
	"vagrant@10.0.0.5${GPU01}:mpi-hello.c"

# Compile the program
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	mpicc -o ./mpi-hello mpi-hello.c

# Run with srun
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun --mpi=pmix -n 2 '~/mpi-hello'
