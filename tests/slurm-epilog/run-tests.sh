#!/usr/bin/env bash
# Regression tests for the Slurm epilog cleanup scope.
#
# The slurm role is excluded from the molecule CI because it needs systemd
# services a container cannot run, so these scripts have had no automated
# cover. What they do is destructive -- `killall -9 -u`, `rm -fr` -- and the
# failure mode is silent: a cleanup that reaps a bystander looks exactly like a
# cleanup that worked. The cases below pin the guards that decide *whether* to
# reap; they need neither Slurm nor root.
#
# The templates are rendered first (render.py) so that what runs here is the
# form a deployment gets, not a trimmed copy.
#
# Usage: tests/slurm-epilog/run-tests.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
templates="$repo/roles/slurm/templates/etc/slurm"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "${2-}"; fail=$((fail + 1)); }

render() {
    # $1 = template path relative to $templates, $2 = output path
    python3 "$here/render.py" "$templates/$1" "$2" || return 1
    chmod +x "$2"
    # A rendered script that does not parse would fail every behavioural case
    # below with the same opaque message; check the syntax separately so the
    # cause is named.
    bash -n "$2"
}

# ---------------------------------------------------------------------------
# run-parts.sh: which jobs count as "the user still has work on this node"
# ---------------------------------------------------------------------------
#
# The harness drives the real script with a stub squeue on PATH. The stub reads
# its scripted answer from $SQUEUE_FIXTURE so each case controls both the
# output and the exit status.

setup_runparts() {
    local dir="$work/runparts"
    rm -rf "$dir"
    mkdir -p "$dir/bin" "$dir/parts"

    render "shared/bin/run-parts.sh" "$dir/run-parts.sh" || return 1

    # The script calls squeue twice: once for the exclusive check (-o "%C %D"),
    # once for the last-user-job count. Answer the first with a non-exclusive
    # allocation so only the second is under test.
    # The stub must honour -t. A stub that answers the same way whatever states
    # were asked for would let the pre-fix script pass the SUSPENDED case too,
    # and the test would prove nothing. $SQUEUE_JOBS is "id:STATE" per line and
    # the stub returns only the ids whose state was requested -- which is what
    # the real squeue does, and what the fix depends on.
    cat > "$dir/bin/squeue" <<'STUB'
#!/usr/bin/env bash
want_states=""
prev=""
for arg in "$@"; do
    if [ "$arg" = "%C %D" ]; then
        echo "1 1"
        exit 0
    fi
    case "$prev" in
        -t|--states) want_states="$arg" ;;
    esac
    case "$arg" in
        -t*) [ "$arg" != "-t" ] && want_states="${arg#-t}" ;;
        --states=*) want_states="${arg#--states=}" ;;
    esac
    prev="$arg"
done

if [ -n "${SQUEUE_RC:-}" ] && [ "$SQUEUE_RC" != 0 ]; then
    exit "$SQUEUE_RC"
fi

[ -n "${SQUEUE_JOBS:-}" ] || exit 0

printf '%s\n' "$SQUEUE_JOBS" | while IFS=: read -r id state; do
    [ -n "$id" ] || continue
    # No -t at all means squeue's default; the scripts under test always pass
    # one, so treat a missing filter as "match everything" rather than guess.
    if [ -z "$want_states" ]; then
        printf '%s\n' "$id"
        continue
    fi
    case ",${want_states}," in
        *",${state},"*) printf '%s\n' "$id" ;;
    esac
done
exit 0
STUB
    chmod +x "$dir/bin/squeue"

    # The script resolves squeue as {{ slurm_install_prefix }}/bin/squeue, so
    # the stub has to sit at that absolute path rather than merely on PATH.
    mkdir -p "$dir/usr/bin"
    cp "$dir/bin/squeue" "$dir/usr/bin/squeue"
    sed -i "s#^squeue_bin=.*#squeue_bin=\"$dir/usr/bin/squeue\"#" "$dir/run-parts.sh"

    # run-parts.sh appends every child script's output to a fixed path under
    # /var/log/slurm. A machine running the tests need not have it, and a
    # failed redirect makes the child look like it failed, so send it to the
    # fixture instead.
    mkdir -p "$dir/log"
    sed -i "s#/var/log/slurm/prolog-epilog#$dir/log/prolog-epilog#" "$dir/run-parts.sh"

    # A marker script that records whether it ran. The -lastuserjob- infix is
    # what run-parts.sh gates on.
    cat > "$dir/parts/42-lastuserjob-marker" <<STUB
#!/usr/bin/env bash
touch "$dir/RAN"
STUB
    chmod +x "$dir/parts/42-lastuserjob-marker"

    printf '%s' "$dir"
}

runparts_case() {
    # $1 = label, $2 = expected ran|skipped, $3 = jobs as "id:STATE" lines,
    # $4 = SQUEUE_RC
    local label="$1" expect="$2" jobs="${3-}" rc="${4-0}"
    local dir
    dir="$(setup_runparts)" || { no "$label" "harness setup failed"; return; }

    rm -f "$dir/RAN"
    local out
    out=$(
        SLURM_JOB_USER=alice SLURM_JOB_ID=1000 SLURMD_NODENAME=node1 \
        HOSTNAME=node1 SLURM_JOBID=1000 \
        SQUEUE_JOBS="$jobs" SQUEUE_RC="$rc" \
        "$dir/run-parts.sh" "$dir/parts" 2>&1
    )

    local actual=skipped
    [ -e "$dir/RAN" ] && actual=ran

    if [ "$actual" = "$expect" ]; then
        ok "$label"
    else
        no "$label" "expected $expect, got $actual -- $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
    fi
}

echo "run-parts.sh -- last-user-job gate"
runparts_case "no other job of this user runs the cleanup"            ran     ""
runparts_case "another RUNNING job blocks the cleanup"                skipped "1001:running"
# The reason this issue exists: a suspended job owns processes and files but
# never appeared under "-t running".
runparts_case "a SUSPENDED job blocks the cleanup"                    skipped "1002:suspended"
runparts_case "a CONFIGURING job blocks the cleanup"                  skipped "1003:configuring"
# A failed lookup is not evidence of absence.
runparts_case "squeue failure blocks the cleanup"                     skipped "" 1
# The epilog's own job must not count as "another job", or the cleanup would
# never run again.
runparts_case "the job's own id does not block its cleanup"           ran     "1000:running"
runparts_case "own id plus a sibling job still blocks"                skipped "1000:running
1004:running"

# ---------------------------------------------------------------------------
# 42-lastuserjob-cleanup: whose files may be deleted
# ---------------------------------------------------------------------------

setup_cleanup() {
    local dir="$work/cleanup"
    rm -rf "$dir"
    mkdir -p "$dir/etc/slurm" "$dir/bin"

    render "epilog.d/42-lastuserjob-cleanup" "$dir/42-cleanup" || return 1
    # Point the rendered script at the fixture's localusers.backup.
    sed -i "s#^localusers_backup=.*#localusers_backup='$dir/etc/slurm/localusers.backup'#" "$dir/42-cleanup"

    printf '%s' "$dir"
}

echo
echo "42-lastuserjob-cleanup -- deletion guards"

# --- listed operator: files must survive -----------------------------------
dir="$(setup_cleanup)"
printf 'alice\nbob\n' > "$dir/etc/slurm/localusers.backup"
out=$(SLURM_JOB_USER=alice "$dir/42-cleanup" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'Removed residual'; then
    ok "a user listed in localusers.backup is spared"
else
    no "a user listed in localusers.backup is spared" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
fi

# --- unreadable list: must not authorise deletion --------------------------
dir="$(setup_cleanup)"
# No localusers.backup at all -> grep exits 2, which is "lookup failed", not
# "not listed".
out=$(SLURM_JOB_USER=alice "$dir/42-cleanup" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'localusers lookup failed'; then
    ok "an unreadable localusers.backup stops the cleanup"
else
    no "an unreadable localusers.backup stops the cleanup" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
fi

# --- unresolvable account: must not delete on a partial listing ------------
dir="$(setup_cleanup)"
: > "$dir/etc/slurm/localusers.backup"
out=$(SLURM_JOB_USER=nosuchuser-$$ "$dir/42-cleanup" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'cannot resolve'; then
    ok "an unresolvable owner stops the cleanup"
else
    no "an unresolvable owner stops the cleanup" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
fi

# --- root and empty user are left alone ------------------------------------
dir="$(setup_cleanup)"
: > "$dir/etc/slurm/localusers.backup"
out=$(SLURM_JOB_USER=root "$dir/42-cleanup" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'Removed residual'; then
    ok "root is left alone"
else
    no "root is left alone" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
fi

# --- the walk stays on one filesystem --------------------------------------
# -xdev is what keeps the epilog out of a job_container/tmpfs private /tmp, a
# user's sshfs, or a bind mount of shared storage that another node's job is
# still using. Proving it needs a real mount, so this case is skipped when the
# harness cannot make one.
# The script skips root by design, so the fixture needs a real unprivileged
# account that owns the files.
victim_user=""
for candidate in nobody rocky ubuntu daemon; do
    if id -u -- "$candidate" >/dev/null 2>&1; then
        victim_user="$candidate"
        break
    fi
done

if [ "$(id -u)" = 0 ] && [ -n "$victim_user" ] && command -v mount >/dev/null 2>&1; then
    dir="$(setup_cleanup)"
    : > "$dir/etc/slurm/localusers.backup"

    mkdir -p "$dir/tmp/sub"
    if mount -t tmpfs tmpfs "$dir/tmp/sub" 2>/dev/null; then
        touch "$dir/tmp/on-this-fs" "$dir/tmp/sub/on-the-submount"
        chown "$victim_user" "$dir/tmp/on-this-fs" "$dir/tmp/sub/on-the-submount"
        # Redirect the script's two hard-coded directories at the fixture.
        sed -i "s#^    for dir in /tmp /dev/shm ; do#    for dir in $dir/tmp ; do#" "$dir/42-cleanup"
        SLURM_JOB_USER="$victim_user" "$dir/42-cleanup" >/dev/null 2>&1

        if [ ! -e "$dir/tmp/on-this-fs" ] && [ -e "$dir/tmp/sub/on-the-submount" ]; then
            ok "-xdev keeps the walk off a submount"
        else
            no "-xdev keeps the walk off a submount" \
               "this-fs exists=$([ -e "$dir/tmp/on-this-fs" ] && echo yes || echo no), submount exists=$([ -e "$dir/tmp/sub/on-the-submount" ] && echo yes || echo no)"
        fi
        umount "$dir/tmp/sub" 2>/dev/null
    else
        printf '  skip -xdev keeps the walk off a submount (could not mount tmpfs)\n'
    fi
else
    printf '  skip -xdev keeps the walk off a submount (needs root and an unprivileged account)\n'
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
