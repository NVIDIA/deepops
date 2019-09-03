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
num_nodes=$(scontrol show hostnames | wc -l)
num_cpus=$(grep -c ^processor /proc/cpuinfo)
numcpus_all=$(( num_nodes * num_cpus ))  # assumes same number of CPUs for each node in the allocation
numcpus_job=$(scontrol show job "$SLURM_JOB_ID" | grep -Eo 'TRES=\S+' | cut -d'=' -f2- | tr ',' '\n' | awk -F= '($1 == "cpu"){print $2}')
if [ "$numcpus_job" == "$numcpus_all" ] ; then
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

    # setup logfiles
    logfile={{ slurm_log_dir }}/prolog-epilog
    stdoutlog="$(mktemp)"
    stderrlog="$(mktemp)"

    log "Running $script ..."
    if ! $script >"$stdoutlog" 2>"$stderrlog"; then
        log "[ERROR] $script failed. Check the log at $logfile for more details."
        failed=1
    fi

    # Allows the task prolog output to be parsed.
    cat "$stdoutlog" || true

    # cleanup logfiles
    echo ">>> $script STDOUT" >>"$logfile" || true
    cat "$stdoutlog" >>"$logfile" || true
    echo ">>> $script STDERR" >>"$logfile" || true
    cat "$stderrlog" >>"$logfile" || true
    rm -f "$stdoutlog" "$stderrlog"
done

if [ "$failed" = "1" ]; then
    log "One or more scripts failed."
    exit 1
fi
