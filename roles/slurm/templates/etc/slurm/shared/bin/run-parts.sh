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
#
# The lookup runs inside a conditional on purpose. This script has "set -e", so
# a bare assignment from a failing squeue aborts the whole prolog/epilog run and
# fails the job; redirecting stderr does not suppress the exit status. A failed,
# empty or non-numeric lookup must instead leave exclusive=0, which only skips
# the *-exclusive-* scripts and lets every other script run.
exclusive=0
if job_alloc=$("$squeue_bin" -h -j "$SLURM_JOBID" -o "%C %D" 2>/dev/null); then
    read -r numcpus_job numnodes_job <<<"$job_alloc" || true
    if [[ "$numcpus_job" =~ ^[0-9]+$ ]] && [[ "$numnodes_job" =~ ^[0-9]+$ ]]; then
        numcpus_sys=$(( $(grep -c ^processor /proc/cpuinfo) * numnodes_job ))
        if [ "$numcpus_sys" -eq "$numcpus_job" ]; then
            exclusive=1
        fi
    else
        log "[WARN] squeue returned no usable allocation for job ${SLURM_JOBID} ('${job_alloc}'); treating the job as non-exclusive."
    fi
else
    log "[WARN] squeue failed for job ${SLURM_JOBID}; treating the job as non-exclusive."
fi

# Find out if there are any more jobs on this node for this user.
# Same reasoning as above with one difference: a failed lookup must not be read
# as "no other jobs", because that would run the *-lastuserjob-* cleanup scripts
# while another job of the same user is still on the node. Piping squeue into
# "wc -l" also hides its exit status, so the status is captured explicitly.
#
# RUNNING alone is too narrow. A job that is SUSPENDED (scontrol suspend, or
# preempted with SuspendTime) or STOPPED still owns its processes, its files in
# /tmp and /dev/shm, and its enroot directories; a job that is CONFIGURING or
# RESIZING has an allocation on this node and is about to. None of those appear
# under "-t running", so the *-lastuserjob-* scripts would run and reap them.
#
# COMPLETING is deliberately absent. The epilog runs while its own job is in
# that state, so including it would make every job find itself, leave
# last_user_job at 0, and disable the cleanup entirely.
lastuserjob_states='running,suspended,stopped,configuring,resizing'
last_user_job=0
if user_jobs=$("$squeue_bin" -h -u "$SLURM_JOB_USER" -w "$HOSTNAME" -t "$lastuserjob_states" -o '%i' 2>/dev/null); then
    # Drop this job's own entry defensively. It should not be in the states
    # above, but an id match is cheap and keeps a future state addition from
    # silently switching the cleanup off.
    other_jobs=$(printf '%s\n' "$user_jobs" | grep -vxF "$SLURM_JOB_ID" || :)
    if [ -z "$other_jobs" ]; then
        last_user_job=1
    fi
else
    log "[WARN] squeue failed while counting jobs for ${SLURM_JOB_USER} on ${HOSTNAME}; not running the last-user-job scripts."
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
