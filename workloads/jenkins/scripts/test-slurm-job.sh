#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Get Slurm cluster info
ssh -v \
        -o "StrictHostKeyChecking no" \
        -o "UserKnownHostsFile /dev/null" \
        -l vagrant \
        -i "${HOME}/.ssh/id_rsa" \
        "10.0.0.5${GPU01}" \
        sinfo --all --long

# Check for drained or down nodes
ssh -v \
        -o "StrictHostKeyChecking no" \
        -o "UserKnownHostsFile /dev/null" \
        -l vagrant \
        -i "${HOME}/.ssh/id_rsa" \
        "10.0.0.5${GPU01}" \
        sinfo --all --list-reasons --long

# Check available MPI options
ssh -v \
        -o "StrictHostKeyChecking no" \
        -o "UserKnownHostsFile /dev/null" \
        -l vagrant \
        -i "${HOME}/.ssh/id_rsa" \
        "10.0.0.5${GPU01}" \
        srun --mpi=list

# Run a simple one-task job
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun -n1 hostname

# Run a simple one-GPU job
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun -n1 -G1 nvidia-smi -L
