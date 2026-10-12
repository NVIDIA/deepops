#!/usr/bin/env bash
# Helpers for job-scoped epilog cleanup (slurm_epilog_cleanup_scope: job).
#
# Sourced by shared/bin/run-parts.sh and epilog.d/40-lastuserjob-processes.
# Deployed only when the scope is "job".
#
# The question these answer is "whose is this process?", asked of the node
# instead of the controller. squeue reports what the controller believes, which
# can lag the node and cannot see a job placed here a moment ago. The kernel's
# /proc/<pid>/cgroup cannot be out of date: Slurm puts every process of a job
# in a cgroup named job_<jobid> (cgroup v1: /slurm/uid_N/job_M/..., cgroup v2:
# .../slurmstepd.scope/job_M/...), so the job id is read straight off the path.
#
# Everything here fails closed. "Could not tell" is reported as such and the
# caller treats it as "another job may be here": cleanup is skipped and logged,
# never guessed. A skipped cleanup is a delay, since it runs again when the
# next job of the user ends. A wrong guess destroys a running job.
#
# The caller sets epilog_proc_root (normally /proc) before sourcing, so that
# the unit tests can supply a fake process tree. It is set by the script, not
# read from the environment.

: "${epilog_proc_root:?epilog_proc_root must be set by the caller}"

# epilog_resolve_uid
#   Sets epilog_uid from SLURM_JOB_UID, or from the account name when that is
#   missing. Returns 1 when no numeric uid can be established.
epilog_resolve_uid() {
    epilog_uid=""
    if [[ "${SLURM_JOB_UID:-}" =~ ^[0-9]+$ ]]; then
        epilog_uid="$SLURM_JOB_UID"
        return 0
    fi
    local resolved
    if resolved=$(id -u -- "${SLURM_JOB_USER:-}" 2>/dev/null) && [[ "$resolved" =~ ^[0-9]+$ ]]; then
        epilog_uid="$resolved"
        return 0
    fi
    return 1
}

# epilog_pid_owned_by UID PID
#   True when the real or effective uid of PID is UID. /proc/<pid>/status is
#   used rather than the owner of /proc/<pid>, which turns root-owned for a
#   process that has made itself non-dumpable.
#   Returns 0 owned, 1 not owned or gone.
epilog_pid_owned_by() {
    local uid="$1" pid="$2" key real eff rest
    local status="$epilog_proc_root/$pid/status"
    [ -r "$status" ] || return 1
    while read -r key real eff rest; do
        if [ "$key" = "Uid:" ]; then
            [ "$real" = "$uid" ] || [ "$eff" = "$uid" ]
            return
        fi
    done <"$status" 2>/dev/null
    return 1
}

# epilog_pid_jobs PID
#   Prints the job id of every job_<id> cgroup component in
#   /proc/<pid>/cgroup, one per line (none printed means the process is in no
#   Slurm job cgroup).
#   Returns 0 parsed, 1 the process is gone, 2 unreadable or not understood.
epilog_pid_jobs() {
    local pid="$1" file content line path
    file="$epilog_proc_root/$pid/cgroup"
    # The redirect has to wrap the whole command: bash reports a failed read of
    # $(<file) itself, and a process that exits mid-scan is routine.
    if ! { content=$(<"$file"); } 2>/dev/null; then
        [ -e "$file" ] || return 1
        return 2
    fi
    [ -n "$content" ] || return 2
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # hierarchy-id:controllers:path, with an empty controller list on v2.
        if [[ ! "$line" =~ ^[0-9]+:[^:]*:/ ]]; then
            return 2
        fi
        path="${line#*:*:}"
        if [[ "$path" =~ (^|/)job_([0-9]+)(/|$) ]]; then
            printf '%s\n' "${BASH_REMATCH[2]}"
        fi
    done <<<"$content"
    return 0
}

# epilog_user_pids UID
#   Prints the pid of every process owned by UID.
#   Returns 0 on success and 2 when the process table is unusable (nothing
#   listed at all), which the caller must treat as "cannot tell".
epilog_user_pids() {
    local uid="$1" entry pid listed=0
    for entry in "$epilog_proc_root"/[0-9]*; do
        [ -d "$entry" ] || continue
        pid="${entry##*/}"
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        listed=1
        if epilog_pid_owned_by "$uid" "$pid"; then
            printf '%s\n' "$pid"
        fi
    done
    [ "$listed" = 1 ] || return 2
    return 0
}

# epilog_other_job_present UID ENDING_JOBID
#   Is any process of UID inside the cgroup of a job other than ENDING_JOBID?
#   Returns 0 yes, 1 no, 2 cannot tell (unreadable or unrecognised cgroup
#   data, or no process table).
epilog_other_job_present() {
    local uid="$1" ending="$2" pid pids jobs job rc unsure=0
    if ! pids=$(epilog_user_pids "$uid"); then
        return 2
    fi
    for pid in $pids; do
        rc=0
        jobs=$(epilog_pid_jobs "$pid") || rc=$?
        case "$rc" in
            0) ;;
            1) continue ;;
            *) unsure=1; continue ;;
        esac
        for job in $jobs; do
            if [ "$job" != "$ending" ]; then
                return 0
            fi
        done
    done
    [ "$unsure" = 0 ] || return 2
    return 1
}
