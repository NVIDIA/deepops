#!/usr/bin/env bash
set -e

logger -s -t slurm-prolog "START user=$SLURM_JOB_USER job=$SLURM_JOB_ID"
{{ slurm_sysconf_dir }}/shared/bin/run-parts.sh {{ slurm_sysconf_dir }}/prolog.d
logger -s -t slurm-prolog "END user=$SLURM_JOB_USER job=$SLURM_JOB_ID"
