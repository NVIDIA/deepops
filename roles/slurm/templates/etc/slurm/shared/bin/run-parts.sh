#!/usr/bin/env bash
# This could all be done with run-parts using regexes on ubuntu.
# However, centos' version of run-parts is just a simple bash script with no useful flags.
set -e
set -o pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 parts_dir"
    exit 1
fi
parts_dir=$1

log () {
    logger -s -t slurm "$@"
}

# Use the configured prefix because slurmd does not inherit it in PATH.
squeue_bin="{{ slurm_install_prefix }}/bin/squeue"

# Find out if we are running in exclusive mode. Failed or incomplete scheduler
# queries fail closed to non-exclusive while ordinary scripts still run.
exclusive=0
numcpus_job=""
numnodes_job=""
if ! numcpus_job=$("$squeue_bin" -h -j "$SLURM_JOBID" -o %C 2>/dev/null); then
    log "Unable to query allocated CPUs for job $SLURM_JOBID; treating it as non-exclusive."
fi
if ! numnodes_job=$("$squeue_bin" -h -j "$SLURM_JOBID" -o %D 2>/dev/null); then
    log "Unable to query allocated nodes for job $SLURM_JOBID; treating it as non-exclusive."
fi
if [[ "$numcpus_job" =~ ^[0-9]+$ ]] &&
   [[ "$numnodes_job" =~ ^[1-9][0-9]*$ ]] &&
   [ $(( $(grep -c ^processor /proc/cpuinfo) * numnodes_job )) -eq "$numcpus_job" ]; then
    exclusive=1
fi

# Find out if there are any more jobs on this node for this user
last_user_job=0
num_jobs=1
if ! num_jobs=$("$squeue_bin" -h -u "$SLURM_JOB_USER" -w "$HOSTNAME" -t running | wc -l); then
    log "Unable to query remaining jobs for $SLURM_JOB_USER; preserving last-user cleanup state."
    num_jobs=1
fi
if [[ ! "$num_jobs" =~ ^[0-9]+$ ]]; then
    log "Invalid remaining-job count for $SLURM_JOB_USER; preserving last-user cleanup state."
    num_jobs=1
fi
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
