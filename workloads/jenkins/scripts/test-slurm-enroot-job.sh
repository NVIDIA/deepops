#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Run a simple one-GPU enroot job
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun -N1 -G1 \
	--container-image="nvcr.io#nvidia/cuda:10.2-base-ubuntu18.04" \
	nvidia-smi -L
