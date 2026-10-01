#!/usr/bin/env bash
# Batch script submitted by run-fixture.sh on behalf of the test user.
#
# It creates the assets the epilog cleanup scripts act on -- a process, a file
# under /tmp, a file under /dev/shm and (when enroot is available) a container
# with a process running inside it -- then parks until the driver releases it.
# Every asset carries the job's tag in its name or path so the driver can tell
# job A's assets from job B's.
#
#   $1 = tag (A, B, ...)
#   $2 = root-owned, read-only control directory
#   $3 = mandatory enroot image (.sqsh)
#   $4 = per-user writable status directory, never used for root control
#
# The driver signals the end of the job by creating $ctl/release-job-$tag.
set -euo pipefail

tag="$1"
ctl="$2"
sqsh="$3"
status="$4"
[[ "$tag" =~ ^[a-zA-Z0-9-]+$ ]] || exit 2
[ -s "$sqsh" ] && [ -d "$status" ] || exit 2

# Everything the driver asserts on is named after the tag.
proc_name="epilog-fixture-proc-${tag}"
ctr_proc_name="epilog-fixture-ctr-${tag}"
tmp_dir="/tmp/epilog-fixture-${tag}"
shm_file="/dev/shm/epilog-fixture-${tag}"
container="epilog-fixture-${tag}"

echo "job ${SLURM_JOB_ID:-?} tag=${tag} user=$(id -un) uid=$(id -u) node=$(hostname -s)"
echo "cgroup: $(cat /proc/self/cgroup 2>/dev/null | tr '\n' ' ')"

mkdir "$tmp_dir"
echo "job ${SLURM_JOB_ID:-?}" > "$tmp_dir/payload"
echo "job ${SLURM_JOB_ID:-?}" > "$shm_file"

# A long-lived process that belongs to this job. `exec -a` renames argv[0] so
# the driver can find it with `pgrep -f` without matching anything else.
setsid bash -c "exec -a ${proc_name} sleep infinity" >/dev/null 2>&1 &
proc_pid=$!
container_pid=""
trap 'kill "$proc_pid" ${container_pid:+"$container_pid"} 2>/dev/null || true' EXIT
echo "started ${proc_name} pid $proc_pid"

command -v enroot >/dev/null
if ! enroot create --name "$container" "$sqsh" >"${status}/enroot-create-${tag}.log" 2>&1; then
    echo create-failed > "$status/enroot-status-$tag"
    exit 2
fi
# The acknowledgement originates inside the container, not from its launcher.
setsid enroot start --mount "$status:/fixture-status" "$container" bash -c \
    "echo ready > /fixture-status/ctr-ready-$tag; exec -a $ctr_proc_name sleep infinity" \
    >"$status/enroot-start-$tag.log" 2>&1 &
container_pid=$!
deadline=$((SECONDS + 60))
while [ ! -s "$status/ctr-ready-$tag" ] || ! pgrep -u "$(id -u)" -f "^$ctr_proc_name( |$)" >/dev/null; do
    if ! kill -0 "$container_pid" 2>/dev/null || [ "$SECONDS" -ge "$deadline" ]; then
        echo start-failed > "$status/enroot-status-$tag"
        exit 2
    fi
    sleep 0.2
done
echo ready > "$status/enroot-status-$tag"

# The driver independently checks all assets before trusting readiness.
echo "${SLURM_JOB_ID:-?}" > "${status}/ready-${tag}"

# Park until released. The timeout keeps a driver crash from leaving a job
# running forever on a shared test node.
deadline=$(( $(date +%s) + ${FIXTURE_JOB_TIMEOUT:-1800} ))
while [ ! -e "${ctl}/release-job-${tag}" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "timed out waiting for release"
        exit 3
    fi
    sleep 0.2
done
echo "released at $(date -u +%FT%TZ)"
exit 0
