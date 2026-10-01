#!/usr/bin/env bash
# Invoked by bash --login: keep the shell itself alive outside a Slurm job.
set -euo pipefail
key=$1
status=$2
shopt -q login_shell || exit 2
[[ "$key" =~ ^[a-zA-Z0-9-]+$ ]] || exit 2
printf '%s\n' "$$" > "$status/login-$key"
ctl="${status%/status-*}/ctl"
deadline=$((SECONDS + 1800))
while [ ! -e "$ctl/release-login-$key" ]; do
    [ "$SECONDS" -lt "$deadline" ] || exit 3
    sleep 1
done
