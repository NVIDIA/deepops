#!/usr/bin/env bash
# This could all be done with run-parts using regexes on ubuntu.
# However, centos' version of run-parts is just a simple bash script with no useful flags.
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 parts_dir"
    exit 1
fi
parts_dir=$1

log () {
    logger -s -t slurm "$@"
}

# Use an absolute path: slurmd's PATH does not include a custom
# slurm_install_prefix, and with an empty command result both sides of the
# comparison below were "" and every job was treated as exclusive.
squeue_bin="{{ slurm_install_prefix }}/bin/squeue"

# Find out if we are running in exclusive mode.
# Ask squeue for allocated CPUs and node count directly instead of parsing
# "scontrol show job": on recent Slurm the pattern TRES=cpu= matched both the
# ReqTRES= and AllocTRES= lines, yielding a multi-line value that never
# compared equal, so exclusive jobs were never detected.
exclusive=0
numcpus_job=$("$squeue_bin" -h -j "$SLURM_JOBID" -o %C 2>/dev/null)
numnodes_job=$("$squeue_bin" -h -j "$SLURM_JOBID" -o %D 2>/dev/null)
numcpus_sys=$(( $(grep -c ^processor /proc/cpuinfo) * ${numnodes_job:-1} ))
if [ -n "$numcpus_job" ] && [ "$numcpus_sys" -eq "$numcpus_job" ] 2>/dev/null ; then
    exclusive=1
fi

# Find out if there are any more jobs on this node for this user
last_user_job=0
num_jobs=$("$squeue_bin" -h -u "$SLURM_JOB_USER" -w "$HOSTNAME" -t running | wc -l)
if [ "$num_jobs" -eq 0 ]; then
    last_user_job=1
fi

# Re-implement run-parts since on centos it is just a bash script with no useful flags.
failed=0
for script in "$parts_dir"/*; do
    if [ ! -x "$script" ]; then
        log "Skipping $script because it is not executable."
        continue
    fi
    if [[ "$script" == *"-exclusive-"* ]] && [ "$exclusive" = 0 ]; then
        log "Skipping $script because the job was not run in exclusive mode."
        continue
    fi
    if [[ "$script" == *"-lastuserjob-"* ]] && [ "$last_user_job" = 0 ]; then
        log "Skipping $script because there is still another job running on this node for the same user."
        continue
    fi
    log "Running $script ..."
    if ! $script >>/var/log/slurm/prolog-epilog 2>&1; then
        log "[ERROR] $script failed. Check the log at /var/log/slurm/prolog-epilog for more details."
        failed=1
    fi
done

if [ "$failed" = "1" ]; then
    log "One or more scripts failed."
    exit 1
fi
