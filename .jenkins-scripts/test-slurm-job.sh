#!/bin/bash
pwd
GPU="$(echo "${GPUDATA}" | cut -d"-" -f1)"
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.4${GPU}" \
	srun -n1 hostname
