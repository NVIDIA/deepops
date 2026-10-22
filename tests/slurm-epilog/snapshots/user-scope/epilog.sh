#!/usr/bin/env bash
set -e

logger -s -t slurm-epilog "START user=$SLURM_JOB_USER job=$SLURM_JOB_ID"
/etc/slurm/shared/bin/run-parts.sh /etc/slurm/epilog.d
logger -s -t slurm-epilog "END user=$SLURM_JOB_USER job=$SLURM_JOB_ID"
