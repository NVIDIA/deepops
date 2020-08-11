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

# Find out if we are running in exclusive mode
exclusive=0
numcpus_sys=$(( $(grep -c ^processor /proc/cpuinfo) * $(scontrol show job "$SLURM_JOBID" | grep -Eio "TRES=.*node=[0-9]+" | cut -d= -f5) ))
numcpus_job=$(scontrol show job "$SLURM_JOBID" | grep -Eio "TRES=cpu=[0-9]+" | cut -d= -f3)
if [ "$numcpus_sys" == "$numcpus_job" ] ; then
    exclusive=1
fi

# Find out if there are any more jobs on this node for this user
last_user_job=0
num_jobs=$(squeue -h -u "$SLURM_JOB_USER" -w "$HOSTNAME" -t running | wc -l)
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
