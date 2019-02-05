#!/usr/bin/env bash

JOB=$1

GRES=$(sudo grep -A4 "gres: gpu state for job ${JOB}" /var/log/slurm/slurmctld.log | grep "gres_bit_alloc" | awk '{print $2}' | cut -d: -f2)

echo Job ${JOB}: GPUs ${GRES}
