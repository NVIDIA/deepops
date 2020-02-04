#!/bin/bash
pwd
# TODO: Move this to a common library
GPU01="$(echo "${GPUDATA}" | cut -d"," -f1 | cut -d"-" -f1)"
ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	srun -n1 hostname
