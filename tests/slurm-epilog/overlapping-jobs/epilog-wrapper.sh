#!/usr/bin/env bash
# TEST ONLY. Explicit operator installation/configuration required (README).
# Installed product epilog remains unchanged. No host network/firewall mutation.
set -uo pipefail
active=/run/deepops-epilog-fixture
job=${SLURM_JOB_ID:-}
if [[ "$job" =~ ^[1-9][0-9]*$ ]] && [ -f "$active/control-path" ]; then
    ctl=$(< "$active/control-path")
    if [[ "$ctl" =~ ^/var/lib/epilog-fixture-[a-f0-9]{12}/ctl$ ]] && [ -f "$ctl/fault-$job" ]; then
        # The driver exclusively creates these root-owned controls. Refuse unsafe
        # state rather than falling back to a real-network cleanup invocation.
        for path in "$active" "$active/control-path" "${ctl%/ctl}" "$ctl" "$ctl/fault-$job"; do
            if [ -L "$path" ] || [ "$(stat -c %u "$path")" != 0 ] || [ $(( 8#$(stat -c %a "$path") & 8#022 )) != 0 ]; then
                logger -t slurm-epilog-fixture 'unsafe fault control; refusing fixture invocation'
                exit 0
            fi
        done
        host_net=$(readlink /proc/self/ns/net)
        # Timeout is synchronous: no background worker can outlive teardown.
        timeout --kill-after=5 180 unshare --net -- /bin/bash -c '
            ctl=$1; job=$2; host_net=$3
            isolated=$(readlink /proc/self/ns/net)
            [ "$isolated" != "$host_net" ] || exit 2
            printf "host=%s isolated=%s\n" "$host_net" "$isolated" > "$ctl/fault-isolated-$job"
            exec /etc/slurm/epilog.sh
        ' fixture "$ctl" "$job" "$host_net" > "$ctl/fault-log-$job" 2>&1
        rc=$?
        printf '%s\n' "$rc" > "$ctl/fault-done-$job"
        # A failed injector is an INCONCLUSIVE fixture, not a reason to drain.
        exit 0
    fi
fi
exec /etc/slurm/epilog.sh
