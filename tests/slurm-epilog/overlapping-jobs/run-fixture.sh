#!/usr/bin/env bash
# Overlapping-jobs fixture for the Slurm epilog cleanup scope (issue #1407).
#
# Runs as root on a single-node Slurm test cluster (controller, login and
# compute on the same host) and drives the *installed* epilog with real jobs:
# it never edits /etc/slurm/epilog.sh, run-parts.sh or the epilog.d scripts
# under test. The only things it adds to the node are two fixture-owned hooks
# in epilog.d (installed for one scenario each and removed afterwards), two
# throwaway accounts. Scenario 6 requires the separately installed test wrapper
# to isolate one epilog in a temporary network namespace (no host firewall).
#
# Scenarios (design note docs/slurm-cluster/epilog-job-scoped-cleanup-design.md,
# section 5; all same user, one node):
#   1  jobs A and B; A ends while B runs           -> B's assets survive
#   2  same, B gang-suspended                        -> B's assets survive
#   3  B is allocated during A's epilog             -> B unaffected
#   4  user's last job ends                         -> orphan, files, enroot dirs removed
#   5  exempt operator with a login shell           -> untouched
#   6  controller unreachable during the epilog     -> nothing deleted, node not drained
#   7  repeat scenarios 1 and 4 on cgroup v2        -> mandatory repetition
#
# --expect current     expectations for the 26.09 (per-user) epilog
# --expect job-scoped  expectations for the job-scoped epilog
# The two differ only in scenario 3, which is the #1407 reproduction.
#
# See README.md for the run procedure and the report format.
set -uo pipefail

FIXTURE_VERSION="2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# options
# ---------------------------------------------------------------------------
EXPECT=current
SCENARIOS="1,2,3,4,5,6,7"
RUN_ID="$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
RUN_KEY="$RUN_ID"
[[ "$RUN_ID" =~ ^[a-f0-9]{12}$ ]] || { echo "could not generate run identity" >&2; exit 2; }
USER_QA="efq_$RUN_ID"
USER_OPS="efo_$RUN_ID"
OUT=""
REPORT_ENABLED=0
SLURM_PREFIX=""
IMAGE="docker://ubuntu:24.04"
SUSPEND_MODE=gang
PARTITION=""
GANG_PARTITION=""
APPROVAL=""
LEASE=""
KEEP_USERS=0
NO_ENROOT=0
SELFTEST=0
BASE="/var/lib/epilog-fixture-$RUN_ID"
ACTIVE=/run/deepops-epilog-fixture
OWNS_SETUP=0
OWNERSHIP_UNCERTAIN=0
EPILOG_DIR=/etc/slurm/epilog.d
LOCALUSERS_BACKUP=/etc/slurm/localusers.backup
NODE=""
WAIT_JOB=360
WAIT_EPILOG=240

usage() {
    cat <<EOF
Usage: $0 [options]
  --expect current|job-scoped   which epilog the expectations describe (default: current)
  --scenarios LIST              nonempty, unique comma list from 1-7 (default: $SCENARIOS)
  --partition NAME              normal partition for scenarios 1,3-7
  --gang-partition NAME         FORCE-sharing partition for scenario 2
  --approval REF                operator-verified authorization reference
  --lease REF                   operator-verified exclusive active lease reference
  --out DIR                     report/evidence directory (default: /root/epilog-fixture-<timestamp>)
  --node NAME                   Slurm node name (default: hostname -s)
  --slurm-prefix DIR            Slurm install prefix holding bin/sbatch (default: autodetect)
  --user NAME                   throwaway job user (default: $USER_QA)
  --operator NAME               throwaway exempt operator (default: $USER_OPS)
  --image URI                   enroot image to import once for the container checks (default: $IMAGE)
  --suspend-mode gang           only actual gang scheduling is supported
  Enroot is mandatory; --no-enroot and --keep-users are rejected.
  --selftest                    offline checks of this script's logic; needs neither root nor Slurm
  -h, --help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --expect|--scenarios|--out|--node|--slurm-prefix|--user|--operator|--image|--suspend-mode|--partition|--gang-partition|--approval|--lease)
            [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "missing value for $1" >&2; exit 2; } ;;
    esac
    case "$1" in
        --partition) PARTITION="$2"; shift 2 ;;
        --gang-partition) GANG_PARTITION="$2"; shift 2 ;;
        --approval) APPROVAL="$2"; shift 2 ;;
        --lease) LEASE="$2"; shift 2 ;;
        --expect) EXPECT="$2"; shift 2 ;;
        --scenarios) SCENARIOS="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --node) NODE="$2"; shift 2 ;;
        --slurm-prefix) SLURM_PREFIX="$2"; shift 2 ;;
        --user) USER_QA="$2"; shift 2 ;;
        --operator) USER_OPS="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --no-enroot) NO_ENROOT=1; shift ;;
        --suspend-mode) SUSPEND_MODE="$2"; shift 2 ;;
        --keep-users) KEEP_USERS=1; shift ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$EXPECT" in current|job-scoped) ;; *) echo "--expect must be current or job-scoped" >&2; exit 2 ;; esac
case "$SUSPEND_MODE" in gang) ;; *) echo "scenario 2 requires actual gang scheduling" >&2; exit 2 ;; esac
[[ "$SCENARIOS" =~ ^[1-7](,[1-7])*$ ]] || { echo "--scenarios requires a nonempty list from 1-7" >&2; exit 2; }
declare -A selected=()
IFS=',' read -r -a wanted <<<"$SCENARIOS"
for s in "${wanted[@]}"; do
    [ -z "${selected[$s]:-}" ] || { echo "duplicate scenario $s" >&2; exit 2; }
    selected[$s]=1
done
for u in "$USER_QA" "$USER_OPS"; do
    [[ "$u" =~ ^[a-z_][a-z0-9_]{0,30}$ ]] && [ "$u" != root ] || { echo "invalid throwaway account" >&2; exit 2; }
done
[ "$USER_QA" != "$USER_OPS" ] || { echo "user and operator must differ" >&2; exit 2; }
for value in "$NODE" "$PARTITION" "$GANG_PARTITION"; do
    [[ "$value" =~ ^[a-zA-Z0-9_.-]*$ ]] || { echo "invalid node/partition" >&2; exit 2; }
done
for value in "$OUT" "$SLURM_PREFIX"; do
    if [ -n "$value" ]; then
        [[ "$value" =~ ^/[a-zA-Z0-9_./-]+$ ]] && [[ "/$value/" != *'/../'* ]] && [[ "/$value/" != *'/./'* ]] && [ "$value" != / ] || { echo "invalid absolute path" >&2; exit 2; }
    fi
done
[ "$NO_ENROOT" = 0 ] || { echo "enroot coverage is mandatory; --no-enroot is not supported" >&2; exit 2; }
[ "$KEEP_USERS" = 0 ] || { echo "--keep-users is not supported; resources must be run-owned" >&2; exit 2; }

CTL="$BASE/ctl"
JOBOUT="$BASE/jobout"
STAGE="$BASE/stage"
JOBSCRIPT="$here/jobs/fixture-job.sh"
HOLD_HOOK_SRC="$here/hooks/10-fixture-hold"
PROBE_HOOK_SRC="$here/hooks/00-fixture-probe"
SQSH=""
declare -A ENROOT_DATA=() ENROOT_RUNTIME=()
CGROUP_MODE=unknown
CTLD_PORT=6817
SBIN=""

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
ts() { date -u +%FT%TZ; }
say() { printf '%s %s\n' "$(ts)" "$*" >&2; [ "$REPORT_ENABLED" = 1 ] && [ -n "$OUT" ] && [ -d "$OUT" ] && printf '%s %s\n' "$(ts)" "$*" >> "$OUT/driver.log"; return 0; }
die() { say "FATAL: $*"; exit 2; }

# ---------------------------------------------------------------------------
# results
# ---------------------------------------------------------------------------
# One row per check: scenario<TAB>check<TAB>expected<TAB>actual<TAB>result
ROWS=()
declare -A SCEN_NOTE=()
declare -A SCEN_RAN=()
declare -A CHECKS=()
declare -A INVALID=()
required_checks() {
    case "$1" in
        1) echo 'ready epilog_end proc tmp shm ctr_dir ctr_runtime ctr_proc orphan node_drained' ;;
        2) echo 'ready epilog_end gang suspended proc tmp shm ctr_dir ctr_runtime ctr_proc orphan node_drained' ;;
        3) echo 'ready epilog_end complete_wait hook_held b_allocated_during_hold proc tmp shm ctr_dir ctr_runtime ctr_proc orphan node_drained' ;;
        4) echo 'ready epilog_end orphan tmp shm ctr_dir ctr_runtime node_drained' ;;
        5) echo 'ready epilog_end login_shell shell tmp shm node_drained' ;;
        6) echo 'ready epilog_end fault_isolated squeue_warn orphan tmp shm ctr_dir ctr_runtime node_drained' ;;
        7) echo 'cgroup_v2 repeat_1 repeat_4' ;;
    esac
}

# What each check should show for the chosen target epilog.
#   proc/ctr_proc/orphan/shell: alive|gone     tmp/shm/ctr_dir: present|absent
#   node_drained: no   squeue_warn: yes   b_allocated_during_hold: yes   hook_held: yes
expected_for() {
    local scenario="$1" item="$2" mode=survive
    case "$item" in
        node_drained) echo no; return ;;
        ready|epilog_end|gang|complete_wait|login_shell|fault_isolated|cgroup_v2|repeat_1|repeat_4|squeue_warn|b_allocated_during_hold|hook_held|suspended) echo yes; return ;;
    esac
    case "$scenario" in
        3) [ "$EXPECT" = current ] && mode=removed ;;
        4) mode=removed ;;
    esac
    case "$item:$mode" in
        proc:survive|ctr_proc:survive|orphan:survive|shell:survive) echo alive ;;
        proc:removed|ctr_proc:removed|orphan:removed|shell:removed) echo gone ;;
        tmp:survive|shm:survive|ctr_dir:survive|ctr_runtime:survive) echo present ;;
        tmp:removed|shm:removed|ctr_dir:removed|ctr_runtime:removed) echo absent ;;
        *) echo "-" ;;
    esac
}

# Items whose expectation is a precondition of the scenario rather than a
# behaviour of the epilog: when they fail the scenario proves nothing.
is_required_item() {
    case "$1" in ready|epilog_end|gang|complete_wait|login_shell|fault_isolated|cgroup_v2|repeat_1|repeat_4|squeue_warn|b_allocated_during_hold|hook_held|suspended) return 0 ;; esac
    return 1
}

classify() {
    # $1 = item, $2 = expected, $3 = actual -> MATCH|MISMATCH|SKIP|INCONCLUSIVE
    local item="$1" expected="$2" actual="$3"
    case "$actual" in
        skip|skipped|n/a|unknown) echo INCONCLUSIVE; return ;;
    esac
    if [ "$expected" = "$actual" ]; then
        echo MATCH
    elif is_required_item "$item"; then
        echo INCONCLUSIVE
    else
        echo MISMATCH
    fi
}

record() {
    # $1 = scenario, $2 = item, $3 = actual, [$4 = label override]
    local scenario="$1" item="$2" actual="$3" label="${4:-$2}" expected result
    expected="$(expected_for "$scenario" "$item")"
    result="$(classify "$item" "$expected" "$actual")"
    CHECKS["$scenario:$item"]=1
    ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s' "$scenario" "$label" "$expected" "$actual" "$result")")
    say "  [$scenario] $label: expected=$expected actual=$actual -> $result"
}

note() { SCEN_NOTE["$1"]="${SCEN_NOTE[$1]:-}${SCEN_NOTE[$1]:+ }$2"; INVALID[$1]=1; say "  [$1] INCONCLUSIVE: $2"; }

scenario_verdict() {
    # $1 = scenario -> MATCH|MISMATCH|INCONCLUSIVE|SKIP|NOT-RUN
    local scenario="$1" row result any=0 mismatch=0 inconclusive=0 nonskip=0
    [ "${SCEN_RAN[$scenario]:-0}" = 1 ] || { echo NOT-RUN; return; }
    local item
    for item in $(required_checks "$scenario"); do
        [ "${CHECKS[$scenario:$item]:-0}" = 1 ] || inconclusive=1
    done
    [ "${INVALID[$scenario]:-0}" = 0 ] || inconclusive=1
    for row in "${ROWS[@]}"; do
        [ "${row%%	*}" = "$scenario" ] || continue
        any=1
        result="${row##*	}"
        case "$result" in
            MISMATCH) mismatch=1; nonskip=1 ;;
            INCONCLUSIVE) inconclusive=1; nonskip=1 ;;
            MATCH) nonskip=1 ;;
        esac
    done
    if [ "$any" = 0 ] || [ "$nonskip" = 0 ]; then echo INCONCLUSIVE
    elif [ "$inconclusive" = 1 ]; then echo INCONCLUSIVE
    elif [ "$mismatch" = 1 ]; then echo MISMATCH
    else echo MATCH
    fi
}

scenario_title() {
    case "$1" in
        1) echo "A ends while B runs" ;;
        2) echo "A ends while B is suspended" ;;
        3) echo "B allocated during A's epilog" ;;
        4) echo "user's last job ends" ;;
        5) echo "exempt operator with a login shell" ;;
        6) echo "controller unreachable during the epilog" ;;
        7) echo "repeat scenarios 1 and 4 on cgroup v2" ;;
        *) echo "scenario $1" ;;
    esac
}

scenario_meaning() {
    # Plain words for the verdict, given the target the expectations describe.
    local scenario="$1" verdict="$2"
    case "$verdict" in
        NOT-RUN|SKIP|INCONCLUSIVE) echo ""; return ;;
    esac
    if [ "$scenario" = 3 ] && [ "$EXPECT" = current ]; then
        [ "$verdict" = MATCH ] && echo "#1407 reproduced: A's epilog destroyed B's assets" \
                               || echo "#1407 NOT reproduced: B's assets survived the race"
        return
    fi
    [ "$verdict" = MATCH ] && echo "behaves as the $EXPECT epilog should" \
                           || echo "does NOT behave as the $EXPECT epilog should"
}

write_report() {
    [ "$REPORT_ENABLED" = 1 ] && [ -n "$OUT" ] || return 0
    local md="$OUT/report.md" tsv="$OUT/report.tsv" json="$OUT/report.json"
    local s v row overall=MATCH
    [ "${RUN_ERROR:-0}" = 0 ] || overall=ERROR
    {
        echo "# Overlapping-jobs epilog fixture report"
        echo
        echo "| field | value |"
        echo "|---|---|"
        echo "| generated | $(ts) |"
        echo "| fixture version | $FIXTURE_VERSION |"
        echo "| expectations for | \`$EXPECT\` epilog |"
        echo "| node | ${NODE:-?} |"
        echo "| cgroup mode | $CGROUP_MODE |"
        echo "| slurm | ${SLURM_VERSION:-?} |"
        echo "| scenarios requested | $SCENARIOS |"
        echo "| epilog fingerprint | see epilog-under-test.txt |"
        echo
        echo "## Verdicts"
        echo
        echo "| scenario | title | verdict | meaning | notes |"
        echo "|---|---|---|---|---|"
        for s in ${SCENARIOS//,/ }; do
            v="$(scenario_verdict "$s")"
            case "$v" in MISMATCH) [ "$overall" = ERROR ] || overall=MISMATCH ;; INCONCLUSIVE|NOT-RUN|SKIP) [ "$overall" = MATCH ] && overall=INCONCLUSIVE ;; esac
            echo "| $s | $(scenario_title "$s") | $v | $(scenario_meaning "$s" "$v") | ${SCEN_NOTE[$s]:-} |"
        done
        echo
        echo "Overall: **$overall** (MATCH = every check agreed with the \`$EXPECT\` expectations; MISMATCH = at least one did not; INCONCLUSIVE = a precondition failed, see notes)."
        echo
        echo "## Checks"
        echo
        echo "| scenario | check | expected | actual | result |"
        echo "|---|---|---|---|---|"
        for row in "${ROWS[@]}"; do
            printf '| %s |\n' "$(printf '%s' "$row" | sed 's/\t/ | /g')"
        done
        echo
        echo "## Evidence files"
        echo
        ls -1 "$OUT" 2>/dev/null | sed 's/^/- /'
    } > "$md" || return 2
    printf 'scenario\tcheck\texpected\tactual\tresult\n' > "$tsv" || return 2
    for row in "${ROWS[@]}"; do printf '%s\n' "$row" >> "$tsv" || return 2; done
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$tsv" "$json" "$EXPECT" "$NODE" "$CGROUP_MODE" "${SLURM_VERSION:-}" "$overall" \
            "$(for s in ${SCENARIOS//,/ }; do printf '%s=%s;' "$s" "$(scenario_verdict "$s")"; done)" <<'PY'
import csv, json, sys
tsv, out, expect, node, cg, slurm, overall, verdicts = sys.argv[1:9]
rows = list(csv.DictReader(open(tsv), delimiter="\t"))
v = dict(x.split("=", 1) for x in verdicts.split(";") if x)
json.dump({"fixture": "slurm-epilog-overlapping-jobs", "expect": expect, "node": node,
           "cgroup_mode": cg, "slurm_version": slurm, "overall": overall,
           "scenario_verdicts": v, "checks": rows}, open(out, "w"), indent=2)
PY
        [ "$?" = 0 ] || return 2
    fi
    say "report written: $md"
    case "$overall" in MATCH) return 0 ;; INCONCLUSIVE) return 3 ;; ERROR) return 2 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# helpers around users, jobs and the node
# ---------------------------------------------------------------------------
as_user() {
    # $1 = user, $2 = command string; a login shell so HOME/XDG paths are the user's
    runuser -l "$1" -c "$2"
}

sq() { "$SBIN/squeue" "$@"; }
sc() { "$SBIN/scontrol" "$@"; }

job_state() { sq -h -j "$1" -o %T; }

wait_for() {
    # $1 = seconds, $2 = description, $3.. = command that exits 0 when done
    local deadline=$(( $(date +%s) + $1 )) desc="$2"; shift 2
    while ! "$@" >/dev/null 2>&1; do
        if [ "$(date +%s)" -ge "$deadline" ]; then say "  timeout waiting for: $desc"; return 1; fi
        sleep 0.5
    done
    return 0
}

job_has_state() { local state; state=$(job_state "$1") || return 2; [ "$state" = "$2" ]; }
job_is_running() { job_has_state "$1" RUNNING; }
job_is_suspended() { job_has_state "$1" SUSPENDED; }
job_is_over() {
    local state
    state=$(job_state "$1") || return 2
    case "$state" in
        ""|COMPLETED|CANCELLED|FAILED|TIMEOUT|NODE_FAIL|PREEMPTED|OUT_OF_MEMORY|BOOT_FAIL|DEADLINE) return 0 ;;
    esac
    return 1
}
file_exists() { [ -e "$1" ]; }

submit_job() {
    # $1 = user, $2 = tag -> job id on stdout
    local user="$1" tag="$RUN_KEY-$2" id
    local args=(-c1 --partition="$PARTITION")
    if [ "${CURRENT_SCENARIO:-}" = 2 ]; then
        local cpus=$((NODE_CPUS - 1))
        [ "$2" != A ] || cpus=1
        args=(-c"$cpus" --oversubscribe --partition="$GANG_PARTITION")
    fi
    id=$(as_user "$user" "$(printf '%q ' "$SBIN/sbatch" --parsable -N1 -n1 "${args[@]}" --mem=1G -w "$NODE" \
            -J "epilog-fixture-$tag" -o "$JOBOUT/%x-%j.out" --export=ALL,FIXTURE_JOB_TIMEOUT=1800 \
            "$JOBSCRIPT" "$tag" "$CTL" "$SQSH" "$BASE/status-$user")" 2>>"$OUT/sbatch.err") || return 1
    id=${id%%;*}
    [[ "$id" =~ ^[1-9][0-9]*$ ]] || { say "  sbatch failed for $user/$tag (see $OUT/sbatch.err)"; return 1; }
    printf '%s\t%s\t%s\n' "$id" "$user" "$tag" >> "$CTL/jobs" || return 1
    printf '%s\t%s\t%s\n' "$id" "$user" "$tag" >> "$OUT/jobs.tsv" || return 1
    say "  submitted job $id ($user, tag $tag)"
    printf '%s' "$id"
}

wait_job_ready() {
    # $1 = job id, $2 = tag; running and its assets created
    wait_for "$WAIT_JOB" "job $1 RUNNING" job_is_running "$1" || return 1
    wait_for 120 "job $1 ($2) assets ready" file_exists "$BASE/status-${3:-$USER_QA}/ready-$RUN_KEY-$2" || return 1
    precheck_job_assets "${3:-$USER_QA}" "$2" || return 1
    say "  job $1 ($2) is running with assets in place"
}

release_job() { : > "$CTL/release-job-$RUN_KEY-$1"; }

epilog_journal() {
    # $1 = since epoch -> the slurm/epilog log lines since then
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --no-pager -o short-iso --since "@$1" \
            -t slurm -t slurm-epilog -t slurm-prolog -t slurm-epilog-fixture 2>/dev/null
    else
        local f
        for f in /var/log/syslog /var/log/messages; do
            [ -r "$f" ] && grep -E 'slurm(-epilog|-prolog|-epilog-fixture)?(\[[0-9]+\])?:' "$f"
        done
    fi
}

epilog_ended() { epilog_journal "$1" | grep -qF "END user=$2 job=$3"; }

wait_epilog_end() {
    # $1 = since, $2 = user, $3 = job id
    wait_for "$WAIT_EPILOG" "epilog END for job $3" epilog_ended "$1" "$2" "$3" || return 1
    record "${CURRENT_SCENARIO:?}" epilog_end yes
}

node_drained() {
    local state
    state=$(sc show node "$NODE" 2>/dev/null) || { echo unknown; return; }
    state=$(printf '%s\n' "$state" | grep -o 'State=[^ ]*' | head -1)
    case "$state" in *DRAIN*) echo yes ;; "") echo unknown ;; *) echo no ;; esac
}

obs_proc() { pgrep -u "$1" -f -- "^$2( |$)" >/dev/null 2>&1 && echo alive || echo gone; }
obs_path() { [ -e "$1" ] && echo present || echo absent; }

start_orphan() {
    # $1 = user, $2 = name. A process of the user's that is in no Slurm job
    # cgroup: started from the driver's session, the way an escaped daemon or a
    # leftover from a non-adopted login would be.
    as_user "$1" "setsid bash -c 'exec -a $2 sleep infinity' >/dev/null 2>&1 &"
    sleep 0.5
    local pid
    pid=$(pgrep -u "$1" -f "^$2( |$)") || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    cp "/proc/$pid/cgroup" "$OUT/$2.cgroup" || return 1
    [ -s "$OUT/$2.cgroup" ] && ! grep -Eq '(^|/)job_[0-9]+' "$OUT/$2.cgroup"
}

enroot_data_path_for() {
    # Cache the validated pre-job path; never rediscover a deletion target.
    [ -z "${ENROOT_DATA[$1]:-}" ] || { printf '%s' "${ENROOT_DATA[$1]}"; return; }
    local raw
    raw=$(awk '$1=="ENROOT_DATA_PATH"{print $2}' /etc/enroot/enroot.conf 2>/dev/null | tail -1)
    [ -n "$raw" ] || raw='${XDG_DATA_HOME:-$HOME/.local/share}/enroot'
    as_user "$1" "echo \"$raw\"" 2>/dev/null | tail -1
}
enroot_runtime_path_for() {
    [ -z "${ENROOT_RUNTIME[$1]:-}" ] || { printf '%s' "${ENROOT_RUNTIME[$1]}"; return; }
    local raw
    raw=$(awk '$1=="ENROOT_RUNTIME_PATH"{print $2}' /etc/enroot/enroot.conf 2>/dev/null | tail -1)
    [ -n "$raw" ] || raw='${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/enroot'
    as_user "$1" "echo \"$raw\"" 2>/dev/null | tail -1
}

enroot_enabled() { [ "$NO_ENROOT" = 0 ] && [ -n "$SQSH" ]; }

ctr_dir_for() { # $1 = user, $2 = tag
    local data; data="$(enroot_data_path_for "$1")"
    [ -n "$data" ] && printf '%s/epilog-fixture-%s' "$data" "$2"
}

record_job_assets() {
    # $1 = scenario, $2 = user, $3 = tag, $4 = label prefix (e.g. "B")
    local s="$1" user="$2" tag="$RUN_KEY-$3" p="$4" ctr
    record "$s" proc "$(obs_proc "$user" "epilog-fixture-proc-$tag")" "$p process"
    record "$s" tmp "$(obs_path "/tmp/epilog-fixture-$tag/payload")" "$p /tmp file"
    record "$s" shm "$(obs_path "/dev/shm/epilog-fixture-$tag")" "$p /dev/shm file"
    if enroot_enabled && [ "$(cat "$BASE/status-$user/enroot-status-$tag" 2>/dev/null)" = ready ]; then
        ctr="$(ctr_dir_for "$user" "$tag")"
        record "$s" ctr_dir "$(obs_path "$ctr")" "$p enroot container dir"
        record "$s" ctr_runtime "$(obs_path "$(enroot_runtime_path_for "$user")")" "$p enroot runtime dir"
        record "$s" ctr_proc "$(obs_proc "$user" "epilog-fixture-ctr-$tag")" "$p enroot container process"
    else
        record "$s" ctr_dir skip "$p enroot container dir"
        record "$s" ctr_proc skip "$p enroot container process"
    fi
}

precheck_job_assets() {
    # $1 = user, $2 = tag; returns 1 and notes when the assets were not created
    local user="$1" tag="$RUN_KEY-$2" missing=""
    [ "$(obs_proc "$user" "epilog-fixture-proc-$tag")" = alive ] || missing="$missing process"
    [ -e "/tmp/epilog-fixture-$tag/payload" ] || missing="$missing /tmp"
    [ -e "/dev/shm/epilog-fixture-$tag" ] || missing="$missing /dev/shm"
    [ "$(cat "$BASE/status-$user/enroot-status-$tag" 2>/dev/null)" = ready ] || missing="$missing enroot-ready"
    [ "$(obs_proc "$user" "epilog-fixture-ctr-$tag")" = alive ] || missing="$missing enroot-process"
    [ -d "$(ctr_dir_for "$user" "$tag")" ] || missing="$missing enroot-dir"
    [ -d "$(enroot_runtime_path_for "$user")" ] || missing="$missing enroot-runtime"
    [ -z "$missing" ] || { say "  precondition: $tag assets missing:$missing"; return 1; }
}

capture_evidence() {
    # $1 = scenario, $2 = since
    local s="$1" since="$2"
    epilog_journal "$since" > "$OUT/scenario-$s.journal.log" 2>/dev/null || { note "$s" "journal capture failed"; return 1; }
    sc show node "$NODE" > "$OUT/scenario-$s.node.txt" 2>&1 || { note "$s" "node evidence query failed"; return 1; }
    sq -h -o '%i %T %u %j %N' > "$OUT/scenario-$s.squeue.txt" 2>&1 || { note "$s" "queue evidence query failed"; return 1; }
    if [ -f /var/log/slurm/prolog-epilog ]; then
        tail -n 200 /var/log/slurm/prolog-epilog > "$OUT/scenario-$s.prolog-epilog.log" 2>/dev/null
    fi
    cp "$JOBOUT"/*.out "$OUT/" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# node mutations the fixture owns, and how they are undone
# ---------------------------------------------------------------------------
HOOKS_INSTALLED=()
LOCALUSERS_SAVED=""
CREATED_USERS=()

install_hook() { # $1 = source path
    local dest="$EPILOG_DIR/$(basename "$1")"
    [ ! -e "$dest" ] && [ ! -L "$dest" ] || return 1
    # noclobber avoids replacing a concurrent hook; root-owned directory required.
    ( set -o noclobber; printf '#!/usr/bin/env bash\nFIXTURE_CTL_DIR=%q\n' "$CTL" > "$dest" ) || return 1
    HOOKS_INSTALLED+=("$dest")
    printf '%s\n' "$dest" >> "$CTL/hooks" || { rm -f -- "$dest"; return 1; }
    tail -n +2 "$1" >> "$dest" && chmod 0755 "$dest" || return 1
    say "  installed fixture hook $dest"
}
remove_hooks() {
    local h
    [ -f "$CTL/hooks" ] || return 0
    while IFS= read -r h; do
        case "$h" in "$EPILOG_DIR/10-fixture-hold"|"$EPILOG_DIR/00-fixture-probe") ;; *) return 1 ;; esac
        rm -f -- "$h" || return 1
        say "  removed fixture hook $h"
    done < "$CTL/hooks"
    : > "$CTL/hooks"
    HOOKS_INSTALLED=()
}

ensure_user() { # Refuse every pre-existing identity, including UID 0 aliases.
    if id -u "$1" >/dev/null 2>&1; then say "  refusing existing user $1"; return 1; fi
    getent group "$1" >/dev/null 2>&1 && return 1
    [ ! -e "$BASE/home-$1" ] && [ ! -L "$BASE/home-$1" ] || return 1
    useradd -U -m -d "$BASE/home-$1" -s /bin/bash "$1" || { OWNERSHIP_UNCERTAIN=1; return 1; }
    CREATED_USERS+=("$1")
    [ "$(id -u "$1")" -gt 0 ] || return 1
    say "  created user $1"
}

remove_owned_path() {
    local path="$1" user="$2" uid
    [ -e "$path" ] || [ -L "$path" ] || return 0
    uid=$(id -u "$user") || return 1
    [ "$uid" -gt 0 ] && [ "$(stat -c %u "$path")" = "$uid" ] || return 1
    rm -rf --one-file-system -- "$path"
}

cleanup_user_assets() { # Only our newly created account and exact run tags.
    local user="$1" owned=0 u tag id owner
    for u in "${CREATED_USERS[@]}"; do [ "$u" != "$user" ] || owned=1; done
    [ "$owned" = 1 ] || return 0
    pkill -9 -u "$user" -f "epilog-fixture-.*$RUN_ID" 2>/dev/null || true
    while IFS=$'\t' read -r id owner tag; do
        [ "$owner" = "$user" ] || continue
        [[ "$tag" == "$RUN_ID-"* ]] || return 1
        remove_owned_path "/tmp/epilog-fixture-$tag" "$user" || return 1
        remove_owned_path "/dev/shm/epilog-fixture-$tag" "$user" || return 1
        as_user "$user" "$(printf '%q ' enroot remove --force "epilog-fixture-$tag")" >/dev/null 2>&1 || true
        [ ! -e "$(ctr_dir_for "$user" "$tag")" ] || return 1
    done < "$CTL/jobs"
    if [ "$user" = "$USER_OPS" ]; then
        remove_owned_path "/tmp/epilog-fixture-$RUN_KEY-OPS" "$user" || return 1
        remove_owned_path "/dev/shm/epilog-fixture-$RUN_KEY-OPS" "$user" || return 1
    fi
    return 0
}

drain_user_jobs() { # Never cancel by user: only IDs returned by our sbatch.
    local id owner tag
    while IFS=$'\t' read -r id owner tag; do
        [ "$owner" = "$1" ] || continue
        [[ "$id" =~ ^[1-9][0-9]*$ ]] || return 1
        job_is_over "$id" && continue
        "$SBIN/scancel" "$id" || return 1
        wait_for 300 "owned job $id to finish" job_is_over "$id" || return 1
    done < "$CTL/jobs"
}

scenario_teardown() {
    [ "$OWNS_SETUP" = 1 ] || return 0
    local id owner tag user remaining
    while IFS=$'\t' read -r id owner tag; do
        : > "$CTL/release-job-$tag"
        : > "$CTL/release-epilog-$id"
    done < "$CTL/jobs"
    drain_user_jobs "$USER_QA" || return 1
    drain_user_jobs "$USER_OPS" || return 1
    # A failed ledger write after sbatch must never permit deleting an account
    # still owning an untracked job. Read by user, but never cancel by user.
    for user in "${CREATED_USERS[@]}"; do
        remaining=$(sq -h -u "$user" -o %i) || return 1
        [ -z "$remaining" ] || return 1
    done
    remove_hooks || return 1
    cleanup_user_assets "$USER_QA" || return 1
    cleanup_user_assets "$USER_OPS" || return 1
    : > "$CTL/release-login-$RUN_KEY"
    if [ -n "$LOCALUSERS_SAVED" ] && [ -f "$LOCALUSERS_SAVED" ]; then
        cp -p "$LOCALUSERS_SAVED" "$LOCALUSERS_BACKUP" || return 1
        say "  restored $LOCALUSERS_BACKUP"
        rm -f "$LOCALUSERS_SAVED"; LOCALUSERS_SAVED=""
    fi
    # Completed IDs can age out of Slurm. Keep history in OUT/jobs.tsv, not
    # the active cancellation ledger used by subsequent scenarios.
    : > "$CTL/jobs"
    return 0
}

FINALISED=0
finalise() {
    local incoming=${1:-0} cleanup_rc=0
    [ "$FINALISED" = 1 ] && return "$incoming"
    FINALISED=1
    [ "$SELFTEST" = 1 ] && return "$incoming"
    if [ "$OWNS_SETUP" = 1 ]; then
        say "teardown"
        if [ "$OWNERSHIP_UNCERTAIN" = 1 ]; then
            cleanup_rc=2
        else
            scenario_teardown || cleanup_rc=2
        fi
        if [ "$cleanup_rc" = 0 ]; then
            local u
            for u in "${CREATED_USERS[@]}"; do
                pkill -9 -u "$u" 2>/dev/null || true
                if [ -n "${ENROOT_DATA[$u]:-}" ]; then
                    remove_owned_path "${ENROOT_DATA[$u]}" "$u" || cleanup_rc=2
                    remove_owned_path "${ENROOT_RUNTIME[$u]}" "$u" || cleanup_rc=2
                fi
                [ "$cleanup_rc" = 0 ] || break
                userdel -r "$u" || cleanup_rc=2
                if getent group "$u" >/dev/null 2>&1; then groupdel "$u" || cleanup_rc=2; fi
            done
            if [ "$cleanup_rc" = 0 ]; then
                rm -rf -- "$BASE"
                rm -f -- "$ACTIVE/control-path"
                rmdir "$ACTIVE" || cleanup_rc=2
            fi
        fi
        [ "$cleanup_rc" = 0 ] || say "cleanup incomplete; retain state at $BASE and lock $ACTIVE for operator recovery"
    fi
    RUN_ERROR=$incoming
    [ "$cleanup_rc" = 0 ] || RUN_ERROR=$cleanup_rc
    write_report; REPORT_RC=$?
    [ "$incoming" = 0 ] || return "$incoming"
    [ "$cleanup_rc" = 0 ] || return "$cleanup_rc"
    return "$REPORT_RC"
}
REPORT_RC=0

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
trusted_path() {
    local path="$1" mode
    while :; do
        [ ! -L "$path" ] && [ "$(stat -c %u "$path")" = 0 ] || return 1
        mode=$(stat -c %a "$path") || return 1
        [ $(( 8#$mode & 8#022 )) = 0 ] || return 1
        [ "$path" != / ] || break
        path=$(dirname "$path")
    done
}

preflight() {
    [ "$(id -u)" = 0 ] || die "run as root"
    [ -n "$APPROVAL" ] && [ -n "$LEASE" ] || die "pass approval and active lease references; see README (not an authorization grant)"
    [ -n "$PARTITION" ] || die "--partition is required"
    local f u jobs config partition_config
    for u in "$USER_QA" "$USER_OPS"; do
        id -u "$u" >/dev/null 2>&1 && die "refusing existing account $u"
        [ ! -e "/home/$u" ] && [ ! -L "/home/$u" ] || die "refusing existing home"
    done
    for f in "$BASE" "$ACTIVE" "$EPILOG_DIR/10-fixture-hold" "$EPILOG_DIR/00-fixture-probe"; do
        [ ! -e "$f" ] && [ ! -L "$f" ] || die "refusing existing state: $f"
    done
    [ -x "$JOBSCRIPT" ] || die "fixture job must be installed executable"
    [ -f "$LOCALUSERS_BACKUP" ] && [ ! -L "$LOCALUSERS_BACKUP" ] || die "localusers.backup must already be a regular file"
    for f in /etc/slurm "$EPILOG_DIR" /run /var/lib "$here" "$JOBSCRIPT" "$HOLD_HOOK_SRC" "$PROBE_HOOK_SRC" "$here/jobs/login-shell.sh" "$LOCALUSERS_BACKUP"; do
        trusted_path "$f" || die "unsafe fixture/system path: $f"
    done
    for f in "$JOBSCRIPT" "$HOLD_HOOK_SRC" "$PROBE_HOOK_SRC"; do
        [ -f "$f" ] || die "missing fixture file $f"
        bash -n "$f" || die "syntax error in $f"
    done
    command -v runuser >/dev/null 2>&1 || die "runuser not found"
    command -v enroot >/dev/null 2>&1 || die "enroot is mandatory"
    command -v journalctl >/dev/null 2>&1 || die "journalctl is mandatory"
    command -v python3 >/dev/null 2>&1 || die "python3 is mandatory for structured reports"

    if [ -z "$SLURM_PREFIX" ]; then
        local c
        for c in /opt/deepops/slurm /usr/local /usr; do
            [ -x "$c/bin/sbatch" ] && { SLURM_PREFIX="$c"; break; }
        done
    fi
    [ -n "$SLURM_PREFIX" ] && [ -x "$SLURM_PREFIX/bin/sbatch" ] || die "sbatch not found; pass --slurm-prefix"
    SBIN="$SLURM_PREFIX/bin"
    for f in sbatch squeue scontrol scancel; do
        trusted_path "$SBIN/$f" || die "unsafe Slurm executable: $SBIN/$f"
    done
    export PATH="$SBIN:$PATH"

    [ -n "$NODE" ] || NODE="$(hostname -s)"
    [ -n "$OUT" ] || OUT="/root/epilog-fixture-$RUN_ID"
    [ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die "output must not exist"
    trusted_path "$(dirname "$OUT")" || die "output ancestors must be root-owned, nonsymlink, not writable by others"

    systemctl is-active slurmctld >/dev/null 2>&1 || die "slurmctld is not active on this host (single-node fixture)"
    systemctl is-active slurmd >/dev/null 2>&1 || die "slurmd is not active on this host"
    SLURM_VERSION="$(sc version 2>/dev/null | head -1)"
    sc show node "$NODE" >/dev/null 2>&1 || die "node $NODE unknown to slurmctld; pass --node"
    [ "$(node_drained)" = no ] || die "node is drained or state query failed"
    if [ "$(hostname -s)" != "$NODE" ]; then
        die "node must equal hostname -s for the dispatcher query"
    fi
    jobs=$(sq -h -o %i) || die "squeue failed during idle check"
    [ -z "$jobs" ] || die "fixture requires an idle, exclusively leased cluster (including no pending jobs)"
    config=$(sc show config) || die "cannot read controller configuration"
    grep -Eq '^ProctrackType[[:space:]]*=[[:space:]]*proctrack/cgroup' <<<"$config" || die "proctrack/cgroup required"
    if [ "${selected[3]:-0}" = 1 ]; then
        grep -Eq '^CompleteWait[[:space:]]*=[[:space:]]*0[[:space:]]*$' <<<"$config" || die "scenario 3 requires CompleteWait=0"
    fi
    if [ "${selected[2]:-0}" = 1 ]; then
        [ -n "$GANG_PARTITION" ] || die "--gang-partition is required for scenario 2"
        grep -Eq '^PreemptMode[[:space:]]*=.*GANG' <<<"$config" || die "PreemptMode must include GANG"
        partition_config=$(sc show partition "$GANG_PARTITION" -o) || die "gang partition query failed"
        grep -Eq 'OverSubscribe=FORCE:[2-9][0-9]*' <<<"$partition_config" || die "gang partition must force sharing"
        NODE_CPUS=$(sc show node "$NODE" -o | grep -o 'CPUTot=[0-9]*' | cut -d= -f2) || die "node CPU query failed"
        [[ "$NODE_CPUS" =~ ^[1-9][0-9]*$ ]] && [ "$NODE_CPUS" -ge 2 ] || die "gang scenario needs at least two CPUs"
    fi
    if [ "${selected[6]:-0}" = 1 ]; then
        grep -Eq '^Epilog[[:space:]]*=[[:space:]]*/etc/slurm/epilog-fixture-wrapper[[:space:]]*$' <<<"$config" || die "scenario 6 requires the reviewed fixture wrapper configured as Epilog"
        trusted_path /etc/slurm/epilog-fixture-wrapper || die "unsafe wrapper path"
        trusted_path "$here/epilog-wrapper.sh" || die "unsafe wrapper source"
        cmp -s "$here/epilog-wrapper.sh" /etc/slurm/epilog-fixture-wrapper || die "installed wrapper differs from fixture"
        command -v unshare >/dev/null || die "unshare required"
    fi

    CTLD_PORT="$(sc show config 2>/dev/null | awk -F'= *' '/^SlurmctldPort/{print $2}' | grep -oE '^[0-9]+' | head -1)"
    [ -n "$CTLD_PORT" ] || CTLD_PORT=6817
    case "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)" in
        cgroup2fs) CGROUP_MODE=v2 ;;
        tmpfs) CGROUP_MODE=v1 ;;
        *) die "cannot determine cgroup mode" ;;
    esac
    [ "${selected[7]:-0}" != 1 ] || [ "$CGROUP_MODE" = v2 ] || die "scenario 7 requires a cgroup v2 node"

    # First mutation: exclusive lock. Nothing is torn down until this succeeds.
    umask 022
    mkdir -m 0755 "$ACTIVE" || die "could not acquire exclusive fixture lock"
    mkdir -m 0755 "$BASE" || { rmdir "$ACTIVE"; die "could not create run state"; }
    mkdir -m 0755 "$CTL" "$JOBOUT" "$STAGE" || die "state setup failed; recover lock manually"
    : > "$CTL/jobs"
    : > "$CTL/hooks"
    OWNS_SETUP=1
    printf '%s\n' "$CTL" > "$ACTIVE/control-path"
    mkdir -m 0700 "$OUT" || die "cannot create output"
    REPORT_ENABLED=1
    printf 'approval=%s\nlease=%s\nrun=%s\nuser=%s\noperator=%s\nbase=%s\n' "$APPROVAL" "$LEASE" "$RUN_ID" "$USER_QA" "$USER_OPS" "$BASE" > "$OUT/ownership.txt"
    printf '%s\n' "$config" > "$OUT/slurm-config.txt"
    [ -z "${partition_config:-}" ] || printf '%s\n' "$partition_config" > "$OUT/gang-partition.txt"
    chmod 1777 "$JOBOUT"
    say "fixture v$FIXTURE_VERSION expect=$EXPECT scenarios=$SCENARIOS node=$NODE out=$OUT"
    {
        echo "node=$NODE hostname=$(hostname -s) cgroup=$CGROUP_MODE slurm='$SLURM_VERSION' ctld_port=$CTLD_PORT"
        sc show config 2>/dev/null | grep -E '^(ProctrackType|TaskPlugin|CompleteWait|PreemptMode|PreemptType|Epilog|Prolog|PrologFlags|KillWait|SlurmctldPort) '
        echo
        echo "epilog scripts under test (sha256):"
        sha256sum /etc/slurm/epilog.sh /etc/slurm/shared/bin/run-parts.sh "$EPILOG_DIR"/* 2>/dev/null | grep -v -- '-fixture-'
        echo
        echo "localusers.backup:"; cat "$LOCALUSERS_BACKUP" 2>/dev/null
        echo
        echo "enroot: $(command -v enroot || echo absent)"
        [ -r /etc/enroot/enroot.conf ] && grep -E '^ENROOT_(DATA|RUNTIME|CACHE)_PATH' /etc/enroot/enroot.conf
    } > "$OUT/epilog-under-test.txt"
    mkdir -p "$OUT/epilog-under-test"
    cp /etc/slurm/epilog.sh /etc/slurm/shared/bin/run-parts.sh "$OUT/epilog-under-test/" 2>/dev/null || true
    cp "$EPILOG_DIR"/* "$OUT/epilog-under-test/" 2>/dev/null || true
    say "  cgroup=$CGROUP_MODE slurm='$SLURM_VERSION' ctld_port=$CTLD_PORT"

    ensure_user "$USER_QA" || die "could not create $USER_QA"
    ensure_user "$USER_OPS" || die "could not create $USER_OPS"
    for u in "$USER_QA" "$USER_OPS"; do
        install -d -m 0700 -o "$u" "$BASE/status-$u" || die "cannot create status directory"
        reserve_enroot_paths "$u" || die "existing, unsafe or shared enroot paths for new account $u"
    done
    chown "$USER_QA" "$STAGE" || die "cannot grant image staging access"
    import_image || die "enroot import failed (see enroot-import.log)"
    chown root:root "$STAGE" "$SQSH" || die "cannot seal image staging"
    chmod 0755 "$STAGE" || die "cannot seal image staging permissions"
}

reserve_enroot_paths() {
    local user="$1" data runtime path other
    data=$(enroot_data_path_for "$user") || return 1
    runtime=$(enroot_runtime_path_for "$user") || return 1
    [[ "$data/" != "$runtime/"* ]] && [[ "$runtime/" != "$data/"* ]] || return 1
    for path in "$data" "$runtime"; do
        [[ "$path" =~ ^/[a-zA-Z0-9_./-]+$ ]] && [[ "/$path/" != *'/../'* ]] && [[ "/$path/" != *'/./'* ]] || return 1
        [[ "$path" != *'//'* ]] && [[ "$path" != */ ]] || return 1
        [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
        for other in "${ENROOT_DATA[@]}" "${ENROOT_RUNTIME[@]}"; do
            [[ "$path/" != "$other/"* ]] && [[ "$other/" != "$path/"* ]] || return 1
        done
    done
    ENROOT_DATA[$user]=$data; ENROOT_RUNTIME[$user]=$runtime
    printf 'enroot_data_%s=%s\nenroot_runtime_%s=%s\n' "$user" "$data" "$user" "$runtime" >> "$OUT/ownership.txt"
}

import_image() {
    SQSH="$STAGE/fixture.sqsh"
    as_user "$USER_QA" "$(printf '%q ' enroot import -o "$SQSH" "$IMAGE")" >"$OUT/enroot-import.log" 2>&1 || return 1
    [ -s "$SQSH" ] && [ ! -L "$SQSH" ] || return 1
    chmod 0644 "$SQSH"
}

# ---------------------------------------------------------------------------
# scenarios
# ---------------------------------------------------------------------------
scenario_1_2() {
    # $1 = 1 (B running) or 2 (B suspended)
    local s="$1" since A B peer
    since=$(date +%s)
    A=$(submit_job "$USER_QA" A) || { note "$s" "could not submit A"; return; }
    wait_job_ready "$A" A || { note "$s" "A never became ready"; return; }
    B=$(submit_job "$USER_QA" B) || { note "$s" "could not submit B"; return; }
    wait_job_ready "$B" B || { note "$s" "B never became ready (did the node have room for two jobs?)"; return; }
    start_orphan "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S$s" || { note "$s" "orphan process did not start"; return; }
    precheck_job_assets "$USER_QA" B || { note "$s" "B's assets incomplete before A ended"; return; }
    record "$s" ready yes

    if [ "$s" = 2 ]; then
        # A uses one CPU; B and a different-user peer compete for N-1 CPUs.
        # The peer keeps a real gang suspension possible after A exits.
        peer=$(submit_job "$USER_OPS" GANGPEER) || { note "$s" "cannot submit gang peer"; return; }
        wait_job_ready "$peer" GANGPEER "$USER_OPS" || { note "$s" "gang peer not ready"; return; }
        wait_for 360 "gang scheduler to suspend B" job_is_suspended "$B" || { note "$s" "B never gang-suspended"; return; }
        job_is_running "$A" || { note "$s" "A not running while B suspended"; return; }
        sc show job "$A" > "$OUT/scenario-2.A-before.txt" || return 2
        sc show job "$B" > "$OUT/scenario-2.B-suspended.txt" || return 2
        record "$s" gang yes
        record "$s" suspended yes
    fi

    say "  ending A ($A) while B ($B) is $(job_state "$B")"
    release_job A
    wait_epilog_end "$since" "$USER_QA" "$A" || note "$s" "no epilog END seen for A within ${WAIT_EPILOG}s"
    wait_for 60 "A over" job_is_over "$A"

    record_job_assets "$s" "$USER_QA" B "B"
    [ "$s" != 2 ] || job_is_suspended "$B" || note "$s" "B no longer suspended after epilog; increase SchedulerTimeSlice and repeat"
    record "$s" orphan "$(obs_proc "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S$s")" "orphan process (no job cgroup)"
    record "$s" node_drained "$(node_drained)" "node drained"
    capture_evidence "$s" "$since"

    release_job B
    wait_for 120 "B over" job_is_over "$B"
}

scenario_3() {
    local s=3 since A B held=no allocated=no
    since=$(date +%s)
    record "$s" complete_wait yes # enforced before setup
    install_hook "$HOLD_HOOK_SRC" || { note "$s" "could not install the hold hook"; return; }
    A=$(submit_job "$USER_QA" A) || { note "$s" "could not submit A"; return; }
    wait_job_ready "$A" A || { note "$s" "A never became ready"; return; }
    : > "$CTL/hold-epilog-$A"
    start_orphan "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S3" || { note "$s" "orphan process did not start"; return; }

    say "  ending A ($A); its epilog will pause after the squeue decision"
    release_job A
    if wait_for 120 "A's epilog to reach the hold" file_exists "$CTL/holding-epilog-$A"; then held=yes; fi
    record "$s" hook_held "$held" "A's epilog paused between squeue and the cleanup scripts"
    if [ "$held" = yes ]; then
        B=$(submit_job "$USER_QA" B) || note "$s" "could not submit B"
        if [ -n "${B:-}" ] && wait_for 90 "B RUNNING during A's epilog" job_is_running "$B"; then
            allocated=yes
            wait_job_ready "$B" B || { note "$s" "B running but assets not ready"; return; }
            [ -e "$CTL/holding-epilog-$A" ] && [ ! -e "$CTL/released-epilog-$A" ] && [ ! -e "$CTL/hold-timeout-epilog-$A" ] || { note "$s" "hold ended before B became ready"; return; }
            job_has_state "$A" COMPLETING || { note "$s" "A not COMPLETING while B allocated"; return; }
            sc show job "$A" > "$OUT/scenario-3.A-held.txt" || return 2
            sc show job "$B" > "$OUT/scenario-3.B-during-hold.txt" || return 2
            record "$s" ready yes
        else
            note "$s" "Slurm did not allocate B to the node while A was COMPLETING (B state: $(job_state "${B:-0}"))"
        fi
        record "$s" b_allocated_during_hold "$allocated" "B allocated and running during A's epilog"
        [ "$allocated" = yes ] && { precheck_job_assets "$USER_QA" B || note "$s" "B's assets incomplete"; }
        : > "$CTL/release-epilog-$A"
    fi
    wait_epilog_end "$since" "$USER_QA" "$A" || note "$s" "no epilog END seen for A"
    [ ! -e "$CTL/hold-timeout-epilog-$A" ] || note "$s" "hold timed out; race not proven"
    wait_for 60 "A over" job_is_over "$A"

    if [ "$allocated" = yes ]; then
        record_job_assets "$s" "$USER_QA" B "B"
        record "$s" orphan "$(obs_proc "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S3")" "orphan process (no job cgroup)"
    fi
    record "$s" node_drained "$(node_drained)" "node drained"
    capture_evidence "$s" "$since"
    remove_hooks
    [ -n "${B:-}" ] && { release_job B; wait_for 120 "B over" job_is_over "$B"; }
}

scenario_4() {
    local s=4 since A
    since=$(date +%s)
    A=$(submit_job "$USER_QA" A) || { note "$s" "could not submit A"; return; }
    wait_job_ready "$A" A || { note "$s" "A never became ready"; return; }
    start_orphan "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S4" || { note "$s" "orphan process did not start"; return; }
    precheck_job_assets "$USER_QA" A || { note "$s" "A's assets incomplete"; return; }
    record "$s" ready yes

    say "  ending A ($A), the user's last job"
    release_job A
    wait_epilog_end "$since" "$USER_QA" "$A" || note "$s" "no epilog END seen for A"
    wait_for 60 "A over" job_is_over "$A"

    # A's own in-job process is killed by Slurm regardless of the epilog, so
    # the process check that matters here is the orphan.
    record "$s" orphan "$(obs_proc "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S4")" "orphan process (no job cgroup)"
    record "$s" tmp "$(obs_path "/tmp/epilog-fixture-$RUN_KEY-A/payload")" "A /tmp file"
    record "$s" shm "$(obs_path "/dev/shm/epilog-fixture-$RUN_KEY-A")" "A /dev/shm file"
    record "$s" ctr_dir "$(obs_path "$(ctr_dir_for "$USER_QA" "$RUN_KEY-A")")" "A enroot container dir"
    record "$s" ctr_runtime "$(obs_path "$(enroot_runtime_path_for "$USER_QA")")" "A enroot runtime dir"
    record "$s" node_drained "$(node_drained)" "node drained"
    capture_evidence "$s" "$since"
}

scenario_5() {
    local s=5 since A
    since=$(date +%s)
    LOCALUSERS_SAVED="$CTL/localusers.backup"
    cp -p "$LOCALUSERS_BACKUP" "$LOCALUSERS_SAVED" || die "cannot preserve exempt users"
    echo "$USER_OPS" >> "$LOCALUSERS_BACKUP" || die "cannot add exempt operator"
    say "  $USER_OPS listed in $LOCALUSERS_BACKUP for this scenario"

    # The operator's login shell and scratch, outside any job.
    # bash -l is a real login shell, not a sleep with a shell-looking argv[0].
    as_user "$USER_OPS" "$(printf '%q ' setsid bash --login "$here/jobs/login-shell.sh" "$RUN_KEY" "$BASE/status-$USER_OPS") >/dev/null 2>&1 &" || { note "$s" "login shell launch failed"; return; }
    wait_for 20 "login shell ready" file_exists "$BASE/status-$USER_OPS/login-$RUN_KEY" || { note "$s" "login shell never ready"; return; }
    local shell_pid
    shell_pid=$(cat "$BASE/status-$USER_OPS/login-$RUN_KEY")
    [[ "$shell_pid" =~ ^[1-9][0-9]*$ ]] && [ "$(stat -c %U "/proc/$shell_pid")" = "$USER_OPS" ] && [ "$(readlink "/proc/$shell_pid/exe")" = "$(readlink -f /bin/bash)" ] || { note "$s" "login shell identity not verified"; return; }
    cp "/proc/$shell_pid/cgroup" "$OUT/scenario-5.login-cgroup.txt" || return 2
    ! grep -Eq '(^|/)job_[0-9]+' "$OUT/scenario-5.login-cgroup.txt" || { note "$s" "login shell was adopted into a job"; return; }
    record "$s" login_shell yes
    as_user "$USER_OPS" "mkdir /tmp/epilog-fixture-$RUN_KEY-OPS && echo shell > /tmp/epilog-fixture-$RUN_KEY-OPS/payload && echo shell > /dev/shm/epilog-fixture-$RUN_KEY-OPS" || return 2

    A=$(submit_job "$USER_OPS" OPSJOB) || { note "$s" "could not submit the operator's job"; return; }
    wait_job_ready "$A" OPSJOB "$USER_OPS" || { note "$s" "operator job never became ready"; return; }
    [ -s "/tmp/epilog-fixture-$RUN_KEY-OPS/payload" ] && [ -s "/dev/shm/epilog-fixture-$RUN_KEY-OPS" ] || { note "$s" "operator scratch not ready"; return; }
    record "$s" ready yes

    say "  ending the operator's last job ($A)"
    release_job OPSJOB
    wait_epilog_end "$since" "$USER_OPS" "$A" || note "$s" "no epilog END seen"
    wait_for 60 "job over" job_is_over "$A"

    record "$s" shell "$(kill -0 "$shell_pid" 2>/dev/null && echo alive || echo gone)" "operator login-shell process"
    record "$s" tmp "$(obs_path "/tmp/epilog-fixture-$RUN_KEY-OPS/payload")" "operator /tmp file"
    record "$s" shm "$(obs_path "/dev/shm/epilog-fixture-$RUN_KEY-OPS")" "operator /dev/shm file"
    record "$s" tmp "$(obs_path "/tmp/epilog-fixture-$RUN_KEY-OPSJOB/payload")" "operator job's /tmp file"
    : > "$CTL/release-login-$RUN_KEY"
    record "$s" node_drained "$(node_drained)" "node drained"
    capture_evidence "$s" "$since"
}

probe_epilog_cgroup() {
    # Optional diagnostic: prints only the v2 cgroup path. Hook ownership is
    # also persisted to the root ledger, so a failed substitution is recoverable.
    local id path
    install_hook "$PROBE_HOOK_SRC" || return 1
    id=$(submit_job "$USER_QA" PROBE) || { remove_hooks; return 1; }
    wait_job_ready "$id" PROBE || return 1
    release_job PROBE
    wait_for 120 "probe epilog" file_exists "$CTL/probe-epilog-$id" || return 1
    wait_for 60 "probe over" job_is_over "$id" || return 1
    remove_hooks
    cp "$CTL/probe-epilog-$id" "$OUT/scenario-6.epilog-cgroup-probe.txt" 2>/dev/null
    path=$(grep -E '^0::' "$CTL/probe-epilog-$id" 2>/dev/null | head -1 | cut -d: -f3- | sed 's#^/##')
    cleanup_user_assets "$USER_QA"
    rm -f "$CTL/release-job-$RUN_KEY-PROBE"
    [ -n "$path" ] || return 1
    printf '%s' "$path"
}

scenario_6() {
    local s=6 since A warn=no
    since=$(date +%s)
    A=$(submit_job "$USER_QA" A) || { note "$s" "could not submit A"; return; }
    wait_job_ready "$A" A || { note "$s" "A never became ready"; return; }
    start_orphan "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S6" || { note "$s" "orphan did not start"; return; }
    precheck_job_assets "$USER_QA" A || { note "$s" "A assets incomplete"; return; }
    record "$s" ready yes
    # The separately installed fixture wrapper isolates only this epilog's
    # network namespace. No host firewall, controller stop or background worker.
    : > "$CTL/fault-$A"
    release_job A
    wait_epilog_end "$since" "$USER_QA" "$A" || { note "$s" "no epilog END"; return; }
    wait_for 120 "isolated epilog finished" file_exists "$CTL/fault-done-$A" || { note "$s" "wrapper did not finish"; return; }
    [ "$(cat "$CTL/fault-done-$A")" = 0 ] && [ -s "$CTL/fault-isolated-$A" ] || { note "$s" "namespace/epilog failed"; return; }
    record "$s" fault_isolated yes
    # Wrapper captures only this invocation's stderr, not another job's warning.
    grep -q 'squeue failed while counting jobs' "$CTL/fault-log-$A" && warn=yes
    record "$s" squeue_warn "$warn"
    record "$s" orphan "$(obs_proc "$USER_QA" "epilog-fixture-$RUN_KEY-orphan-S6")"
    record "$s" tmp "$(obs_path "/tmp/epilog-fixture-$RUN_KEY-A/payload")"
    record "$s" shm "$(obs_path "/dev/shm/epilog-fixture-$RUN_KEY-A")"
    record "$s" ctr_dir "$(obs_path "$(ctr_dir_for "$USER_QA" "$RUN_KEY-A")")"
    record "$s" ctr_runtime "$(obs_path "$(enroot_runtime_path_for "$USER_QA")")"
    record "$s" node_drained "$(node_drained)"
    wait_for 120 "A finished" job_is_over "$A" || note "$s" "A did not complete"
    cp "$CTL/fault-isolated-$A" "$CTL/fault-log-$A" "$CTL/fault-done-$A" "$OUT/" || return 2
    capture_evidence "$s" "$since"
}

scenario_7() {
    [ "$CGROUP_MODE" = v2 ] || { note 7 "requires cgroup v2"; return; }
    record 7 cgroup_v2 yes
    (
        OUT="$OUT/scenario-7"; mkdir -m 0700 "$OUT" || exit 2
        SCENARIOS=1,4; ROWS=(); SCEN_RAN=(); SCEN_NOTE=(); CHECKS=(); INVALID=()
        RUN_KEY="$RUN_ID-s7-1"; CURRENT_SCENARIO=1; SCEN_RAN[1]=1
        scenario_1_2 1
        scenario_verdict 1 > "$CTL/repeat-1"
        scenario_teardown || exit 2
        RUN_KEY="$RUN_ID-s7-4"; CURRENT_SCENARIO=4; SCEN_RAN[4]=1
        scenario_4
        scenario_verdict 4 > "$CTL/repeat-4"
        scenario_teardown || exit 2
        write_report
    ) || note 7 "cgroup v2 repetition did not match; see scenario-7 report"
    record 7 repeat_1 "$([ "$(cat "$CTL/repeat-1" 2>/dev/null)" = MATCH ] && echo yes || echo no)"
    record 7 repeat_4 "$([ "$(cat "$CTL/repeat-4" 2>/dev/null)" = MATCH ] && echo yes || echo no)"
}

# ---------------------------------------------------------------------------
# selftest: logic only, no root, no Slurm
# ---------------------------------------------------------------------------
selftest() {
    local pass=0 fail=0
    ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
    no() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
    eq() { [ "$2" = "$3" ] && ok "$1" || no "$1 (got '$2', want '$3')"; }

    echo "syntax"
    local f
    for f in "$0" "$JOBSCRIPT" "$HOLD_HOOK_SRC" "$PROBE_HOOK_SRC"; do
        bash -n "$f" && ok "bash -n $(basename "$f")" || no "bash -n $f"
    done

    echo "expectations (--expect current)"
    EXPECT=current
    eq "S1 B process survives"            "$(expected_for 1 proc)"    alive
    eq "S2 B /tmp survives"               "$(expected_for 2 tmp)"     present
    eq "S3 B process killed (26.09 race)" "$(expected_for 3 proc)"    gone
    eq "S3 B /tmp removed (26.09 race)"   "$(expected_for 3 tmp)"     absent
    eq "S3 enroot dir removed"            "$(expected_for 3 ctr_dir)" absent
    eq "S4 orphan removed"                "$(expected_for 4 orphan)"  gone
    eq "S4 /tmp removed"                  "$(expected_for 4 tmp)"     absent
    eq "S5 operator shell survives"       "$(expected_for 5 shell)"   alive
    eq "S6 nothing deleted"               "$(expected_for 6 tmp)"     present
    eq "node never drained"               "$(expected_for 6 node_drained)" no
    echo "expectations (--expect job-scoped)"
    EXPECT=job-scoped
    eq "S3 B process survives"            "$(expected_for 3 proc)"    alive
    eq "S3 B /tmp survives"               "$(expected_for 3 tmp)"     present
    eq "S3 orphan survives (B present)"   "$(expected_for 3 orphan)"  alive
    eq "S4 still removes the orphan"      "$(expected_for 4 orphan)"  gone
    EXPECT=current

    echo "classification"
    eq "match"                 "$(classify tmp present present)"            MATCH
    eq "mismatch"              "$(classify tmp present absent)"             MISMATCH
    eq "skip fails closed"     "$(classify ctr_dir present skip)"           INCONCLUSIVE
    eq "precondition -> inconclusive" "$(classify squeue_warn yes no)"      INCONCLUSIVE
    eq "B not allocated -> inconclusive" "$(classify b_allocated_during_hold yes no)" INCONCLUSIVE

    echo "verdicts"
    ROWS=(); SCEN_RAN=(); SCEN_NOTE=(); CHECKS=(); INVALID=()
    complete_rows() { local item; for item in $(required_checks "$1"); do record "$1" "$item" "$(expected_for "$1" "$item")"; done; }
    SCEN_RAN[1]=1; complete_rows 1
    eq "all match -> MATCH" "$(scenario_verdict 1)" MATCH
    SCEN_RAN[3]=1; record 3 hook_held yes >/dev/null; record 3 b_allocated_during_hold no >/dev/null
    eq "precondition failed -> INCONCLUSIVE" "$(scenario_verdict 3)" INCONCLUSIVE
    SCEN_RAN[4]=1; complete_rows 4; record 4 orphan alive >/dev/null
    eq "one mismatch -> MISMATCH" "$(scenario_verdict 4)" MISMATCH
    SCEN_RAN[5]=1; record 5 ctr_dir skip >/dev/null
    eq "only skips -> INCONCLUSIVE" "$(scenario_verdict 5)" INCONCLUSIVE
    eq "not run" "$(scenario_verdict 6)" NOT-RUN
    eq "S3 meaning under current" "$(scenario_meaning 3 MATCH)" "#1407 reproduced: A's epilog destroyed B's assets"

    echo "hold hook"
    local tmpctl rc
    tmpctl="$(mktemp -d "${PAPERCLIP_SCRATCH_DIR:-${TMPDIR:-/tmp}}/epilog-selftest.XXXXXX")"
    FIXTURE_CTL_DIR="$tmpctl" SLURM_JOB_ID=42 timeout 5 bash "$HOLD_HOOK_SRC"; rc=$?
    eq "unmarked job passes straight through" "$rc" 0
    : > "$tmpctl/hold-epilog-43"; : > "$tmpctl/release-epilog-43"
    FIXTURE_CTL_DIR="$tmpctl" SLURM_JOB_ID=43 PATH="$tmpctl:$PATH" timeout 5 bash "$HOLD_HOOK_SRC"; rc=$?
    eq "marked job waits for release and exits 0" "$rc" 0
    [ -e "$tmpctl/holding-epilog-43" ] && ok "hold recorded" || no "hold not recorded"
    [ -e "$tmpctl/released-epilog-43" ] && ok "release recorded" || no "release not recorded"
    : > "$tmpctl/hold-epilog-44"
    ( FIXTURE_CTL_DIR="$tmpctl" SLURM_JOB_ID=44 bash "$HOLD_HOOK_SRC" & hp=$!; sleep 1; [ -e "$tmpctl/holding-epilog-44" ] && kill -0 "$hp" 2>/dev/null; rc=$?; : > "$tmpctl/release-epilog-44"; wait "$hp"; exit $rc )
    eq "marked job really blocks until released" "$?" 0
    FIXTURE_CTL_DIR="$tmpctl" SLURM_JOB_ID=45 bash "$PROBE_HOOK_SRC"; rc=$?
    eq "probe hook exits 0" "$rc" 0
    [ -s "$tmpctl/probe-epilog-45" ] && ok "probe hook records its cgroup" || no "probe hook wrote nothing"
    rm -rf "$tmpctl"

    echo "report"
    OUT="$(mktemp -d "${PAPERCLIP_SCRATCH_DIR:-${TMPDIR:-/tmp}}/epilog-report.XXXXXX")"; REPORT_ENABLED=1; NODE=selftest; CGROUP_MODE=v2; SLURM_VERSION="selftest"
    write_report >/dev/null; rc=$?
    eq "report exit code reflects MISMATCH" "$rc" 1
    grep -q '^| 4 | ' "$OUT/report.md" && ok "report.md has the verdict table" || no "report.md missing verdicts"
    [ -s "$OUT/report.tsv" ] && ok "report.tsv written" || no "report.tsv missing"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; d=json.load(open('$OUT/report.json')); sys.exit(0 if d['overall']=='MISMATCH' and d['scenario_verdicts']['3']=='INCONCLUSIVE' else 1)" \
            && ok "report.json parses with the right verdicts" || no "report.json wrong"
    fi
    rm -rf "$OUT"; OUT=""

    echo
    echo "selftest: $pass passed, $fail failed"
    [ "$fail" = 0 ]
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
if [ "$SELFTEST" = 1 ]; then
    selftest
    exit $?
fi

trap 'rc=$?; trap - EXIT; finalise "$rc"; exit $?' EXIT
trap 'say "interrupted"; exit 130' INT
trap 'say "terminated"; exit 143' TERM

preflight
IFS=',' read -r -a wanted <<<"$SCENARIOS"
for s in "${wanted[@]}"; do
    RUN_KEY="$RUN_ID-s$s"
    CURRENT_SCENARIO="$s"
    say "=== scenario $s: $(scenario_title "$s") ==="
    SCEN_RAN[$s]=1
    case "$s" in
        1|2) scenario_1_2 "$s" ;;
        3) scenario_3 ;;
        4) scenario_4 ;;
        5) scenario_5 ;;
        6) scenario_6 ;;
        7) scenario_7 ;;
    esac
    scenario_rc=$?
    [ "$scenario_rc" = 0 ] || die "scenario execution failed with status $scenario_rc"
    scenario_teardown || die "scenario cleanup failed; preserve state for recovery"
    say "=== scenario $s verdict: $(scenario_verdict "$s") ==="
done
