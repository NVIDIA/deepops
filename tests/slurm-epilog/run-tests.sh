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

# The scripts under test log with `logger`, and they run under `set -e`. On a
# host with no syslog socket -- a CI container, most build agents -- `logger`
# exits non-zero and takes the script down with it, at whatever line it had
# reached. That turns "the guard refused to delete" and "the script died before
# it got there" into the same observation, which is the one distinction these
# tests exist to make. Put a stub on PATH so the log still reaches stderr, where
# the assertions read it, without the exit status.
write_logger_stub() {
    # $1 = directory to place bin/logger in
    mkdir -p "$1/bin"
    cat > "$1/bin/logger" <<'STUB'
#!/usr/bin/env bash
tag=""
while [ $# -gt 0 ]; do
    case "$1" in
        -t) tag="$2"; shift 2 ;;
        -s) shift ;;
        --) shift; break ;;
        -*) shift ;;
        *) break ;;
    esac
done
printf '%s: %s\n' "${tag:-logger}" "$*" >&2
STUB
    chmod +x "$1/bin/logger"
}

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

    write_logger_stub "$dir"

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
        PATH="$dir/bin:$PATH" \
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

# A deterministic identity that resolves on this host and is not root. The
# script skips root by design, so a test that runs as root has to borrow an
# unprivileged account; everyone else can just use their own, whose files they
# can create without chown.
#
# This matters more than it looks. With an unresolvable name the script exits at
# the "cannot resolve" guard before reaching anything else, so a case meant to
# prove the exemption works passes even with the exemption deleted.
cleanup_identity() {
    if [ "$(id -u)" != 0 ]; then
        id -un
        return 0
    fi
    for candidate in nobody rocky ubuntu daemon; do
        if id -u -- "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

own_file() {
    # $1 = owner, $2 = path
    : > "$2" || return 1
    [ "$(id -u)" = 0 ] || return 0
    chown "$1" "$2"
}

setup_cleanup() {
    local dir="$work/cleanup"
    rm -rf "$dir"
    mkdir -p "$dir/etc/slurm" "$dir/roots/tmp" "$dir/roots/shm"
    write_logger_stub "$dir"

    render "epilog.d/42-lastuserjob-cleanup" "$dir/42-cleanup" || return 1
    # Point the rendered script at the fixture's localusers.backup.
    sed -i "s#^localusers_backup=.*#localusers_backup='$dir/etc/slurm/localusers.backup'#" "$dir/42-cleanup"

    # The script deletes under /tmp and /dev/shm. Leaving those pointed at the
    # real directories means that the moment a guard regresses, the suite
    # deletes a real account's scratch and only then reports the failure. Every
    # case gets the fixture roots, including the ones that are supposed to stop
    # before any deletion -- test safety cannot rest on the code under test.
    sed -i "s#^    for dir in /tmp /dev/shm ; do#    for dir in $dir/roots/tmp $dir/roots/shm ; do#" "$dir/42-cleanup"

    # And the redirect is verified rather than assumed: a template edit that
    # changes that line would silently hand the real roots back.
    if ! grep -qF "for dir in $dir/roots/tmp $dir/roots/shm ; do" "$dir/42-cleanup"; then
        printf '  FAIL harness: cleanup roots were not redirected into the fixture\n' >&2
        return 1
    fi
    if grep -qE '^[[:space:]]*for dir in .*(^|[[:space:]])(/tmp|/dev/shm)([[:space:]]|$)' "$dir/42-cleanup"; then
        printf '  FAIL harness: a cleanup root still points outside the fixture\n' >&2
        return 1
    fi

    printf '%s' "$dir"
}

echo
echo "42-lastuserjob-cleanup -- deletion guards"

identity="$(cleanup_identity)" || identity=""
if [ -z "$identity" ]; then
    printf '  skip deletion guards (no resolvable unprivileged account)\n'
else

# Every guard case below puts a file the identity owns under a fixture root and
# asserts it is still there afterwards. Checking only that "Removed residual"
# was absent would pass for a script that deleted everything and failed to log.
guard_case() {
    # $1 = label, $2 = expected log fragment, $3 = SLURM_JOB_USER,
    # $4 = contents of localusers.backup
    local label="$1" expect="$2" user="$3" list="$4"
    local dir
    dir="$(setup_cleanup)" || { no "$label" "harness setup failed"; return; }

    if [ -n "$list" ]; then
        printf '%s\n' "$list" > "$dir/etc/slurm/localusers.backup"
    fi
    own_file "$identity" "$dir/roots/tmp/scratch" || { no "$label" "could not create the fixture file"; return; }

    local out rc
    out=$(PATH="$dir/bin:$PATH" SLURM_JOB_USER="$user" "$dir/42-cleanup" 2>&1); rc=$?

    if [ "$rc" != 0 ]; then
        no "$label" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
    elif [ ! -e "$dir/roots/tmp/scratch" ]; then
        no "$label" "the guard did not stop the deletion: the fixture file is gone"
    elif [ -n "$expect" ] && ! printf '%s' "$out" | grep -q "$expect"; then
        no "$label" "expected the log to mention '$expect'; out=$(printf '%s' "$out" | tail -1)"
    else
        ok "$label"
    fi
}

# --- listed operator: files must survive -----------------------------------
# The identity resolves, so reaching the deletion is a live possibility here;
# only the exemption stops it.
guard_case "a user listed in localusers.backup is spared" "" "$identity" "$identity
bob"

# --- unreadable list: must not authorise deletion --------------------------
# No localusers.backup at all -> grep exits 2, which is "lookup failed", not
# "not listed".
guard_case "an unreadable localusers.backup stops the cleanup" \
    "localusers lookup failed" "$identity" ""

# --- unresolvable account: must not delete on a partial listing ------------
dir="$(setup_cleanup)" || dir=""
if [ -z "$dir" ]; then
    no "an unresolvable owner stops the cleanup" "harness setup failed"
else
    : > "$dir/etc/slurm/localusers.backup"
    own_file "$identity" "$dir/roots/tmp/scratch"
    out=$(PATH="$dir/bin:$PATH" SLURM_JOB_USER=nosuchuser-$$ "$dir/42-cleanup" 2>&1); rc=$?
    if [ "$rc" = 0 ] && [ -e "$dir/roots/tmp/scratch" ] \
       && printf '%s' "$out" | grep -q 'cannot resolve'; then
        ok "an unresolvable owner stops the cleanup"
    else
        no "an unresolvable owner stops the cleanup" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
    fi
fi

# --- root and empty user are left alone ------------------------------------
dir="$(setup_cleanup)" || dir=""
if [ -z "$dir" ]; then
    no "root is left alone" "harness setup failed"
else
    : > "$dir/etc/slurm/localusers.backup"
    own_file "$identity" "$dir/roots/tmp/scratch"
    out=$(PATH="$dir/bin:$PATH" SLURM_JOB_USER=root "$dir/42-cleanup" 2>&1); rc=$?
    if [ "$rc" = 0 ] && [ -e "$dir/roots/tmp/scratch" ] \
       && ! printf '%s' "$out" | grep -q 'Removed residual'; then
        ok "root is left alone"
    else
        no "root is left alone" "rc=$rc out=$(printf '%s' "$out" | tail -1)"
    fi
fi

# --- the cleanup does run when nothing stops it ----------------------------
# Without this the four cases above would all pass for a script that never
# deletes anything, and the guards they pin would be proving nothing.
dir="$(setup_cleanup)" || dir=""
if [ -z "$dir" ]; then
    no "an unlisted, resolvable owner is cleaned up" "harness setup failed"
else
    : > "$dir/etc/slurm/localusers.backup"
    own_file "$identity" "$dir/roots/tmp/scratch"
    out=$(PATH="$dir/bin:$PATH" SLURM_JOB_USER="$identity" "$dir/42-cleanup" 2>&1); rc=$?
    if [ "$rc" = 0 ] && [ ! -e "$dir/roots/tmp/scratch" ]; then
        ok "an unlisted, resolvable owner is cleaned up"
    else
        no "an unlisted, resolvable owner is cleaned up" \
           "rc=$rc file exists=$([ -e "$dir/roots/tmp/scratch" ] && echo yes || echo no) out=$(printf '%s' "$out" | tail -1)"
    fi
fi

fi  # identity

# ---------------------------------------------------------------------------
# 42-lastuserjob-cleanup: the mount boundary
# ---------------------------------------------------------------------------
#
# -xdev bounds the walk. What deletes is `rm -fr`, and these cases are the ways
# a bounded walk still hands it a path that leads off this filesystem:
#
#   - a user-owned directory that holds a mount: the walk stops at the mount,
#     but the parent is selected and the recursive delete goes straight in;
#   - a user-owned mount root: selected in its own right;
#   - a bind mount from the same filesystem: not a boundary to -xdev at all.
#
# Each needs a real mount, so the block is skipped where the harness cannot
# make one.
mount_fixture_ready=no
if [ "$(id -u)" = 0 ] && [ -n "${identity:-}" ] && command -v mount >/dev/null 2>&1 \
   && [ -r /proc/self/mountinfo ]; then
    mount_fixture_ready=yes
fi

if [ "$mount_fixture_ready" != yes ]; then
    printf '  skip mount-boundary cases (needs root, an unprivileged account, mount and /proc/self/mountinfo)\n'
else
    mounted=()
    cleanup_mounts() {
        local i
        for (( i=${#mounted[@]}-1 ; i>=0 ; i-- )); do
            umount "${mounted[$i]}" 2>/dev/null
        done
        mounted=()
    }

    mount_case() {
        # $1 = label, $2 = fixture builder, $3 = assertion
        local label="$1" build="$2" assert="$3" dir
        dir="$(setup_cleanup)" || { no "$label" "harness setup failed"; return; }
        : > "$dir/etc/slurm/localusers.backup"

        if ! "$build" "$dir"; then
            printf '  skip %s (could not build the fixture)\n' "$label"
            cleanup_mounts
            return
        fi

        PATH="$dir/bin:$PATH" SLURM_JOB_USER="$identity" "$dir/42-cleanup" >/dev/null 2>&1
        if "$assert" "$dir"; then
            ok "$label"
        else
            no "$label" "see $dir"
        fi
        cleanup_mounts
    }

    # --- the walk stays off a submount --------------------------------------
    build_submount() {
        local dir="$1"
        mkdir -p "$dir/roots/tmp/sub" || return 1
        mount -t tmpfs tmpfs "$dir/roots/tmp/sub" 2>/dev/null || return 1
        mounted+=( "$dir/roots/tmp/sub" )
        own_file "$identity" "$dir/roots/tmp/on-this-fs" || return 1
        own_file "$identity" "$dir/roots/tmp/sub/on-the-submount" || return 1
    }
    assert_submount() {
        local dir="$1"
        [ ! -e "$dir/roots/tmp/on-this-fs" ] && [ -e "$dir/roots/tmp/sub/on-the-submount" ]
    }
    mount_case "the walk stays off a submount" build_submount assert_submount

    # --- a user-owned parent holding a mount is not deleted recursively ------
    # This is the case -xdev alone does not cover: find stops at the mount, but
    # it still prints the parent, and `rm -fr` on the parent descends into the
    # mount the walk refused to enter.
    build_owned_parent() {
        local dir="$1"
        mkdir -p "$dir/roots/tmp/owned/sub" || return 1
        mount -t tmpfs tmpfs "$dir/roots/tmp/owned/sub" 2>/dev/null || return 1
        mounted+=( "$dir/roots/tmp/owned/sub" )
        chown "$identity" "$dir/roots/tmp/owned" || return 1
        own_file "$identity" "$dir/roots/tmp/owned/beside" || return 1
        own_file "$identity" "$dir/roots/tmp/owned/sub/on-the-mount" || return 1
    }
    assert_owned_parent() {
        local dir="$1"
        # The mount survives, and cleanup still happened around it.
        [ -e "$dir/roots/tmp/owned/sub/on-the-mount" ] \
            && [ ! -e "$dir/roots/tmp/owned/beside" ]
    }
    mount_case "a user-owned parent holding a mount keeps it" \
        build_owned_parent assert_owned_parent

    # --- a user-owned mount root is not emptied -----------------------------
    build_owned_mount_root() {
        local dir="$1"
        mkdir -p "$dir/roots/tmp/scratchmnt" || return 1
        mount -t tmpfs tmpfs "$dir/roots/tmp/scratchmnt" 2>/dev/null || return 1
        mounted+=( "$dir/roots/tmp/scratchmnt" )
        # The mount root itself belongs to the user, so the walk selects it.
        chown "$identity" "$dir/roots/tmp/scratchmnt" || return 1
        own_file "$identity" "$dir/roots/tmp/scratchmnt/payload" || return 1
    }
    assert_owned_mount_root() {
        [ -e "$1/roots/tmp/scratchmnt/payload" ]
    }
    mount_case "a user-owned mount root is left alone" \
        build_owned_mount_root assert_owned_mount_root

    # --- a same-filesystem bind mount is a boundary too ---------------------
    # -xdev compares device numbers, and a bind mount of this same filesystem
    # has the same one, so the walk goes in and deletes the real data.
    build_same_device_bind() {
        local dir="$1"
        mkdir -p "$dir/roots/real" "$dir/roots/tmp/owned/data" || return 1
        own_file "$identity" "$dir/roots/real/keep-me" || return 1
        mount --bind "$dir/roots/real" "$dir/roots/tmp/owned/data" 2>/dev/null || return 1
        mounted+=( "$dir/roots/tmp/owned/data" )
        chown "$identity" "$dir/roots/tmp/owned" || return 1
        own_file "$identity" "$dir/roots/tmp/owned/beside" || return 1
    }
    assert_same_device_bind() {
        local dir="$1"
        [ -e "$dir/roots/real/keep-me" ] && [ ! -e "$dir/roots/tmp/owned/beside" ]
    }
    mount_case "a same-filesystem bind mount is left alone" \
        build_same_device_bind assert_same_device_bind
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
