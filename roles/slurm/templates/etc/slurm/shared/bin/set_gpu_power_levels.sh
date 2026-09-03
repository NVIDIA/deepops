#!/usr/bin/env bash
set -e

case "$1" in
    max)
        query=power.max_limit
        ;;
    default)
        query=power.default_limit
        ;;
    min)
        query=power.min_limit
        ;;
    *)
        echo "Usage: $0 [max,default,min]"
        exit 1
        ;;
esac

# Query every GPU in a single call instead of one call per GPU.
readarray -t limits < <(nvidia-smi --query-gpu="$query" --format=csv,noheader,nounits)

# "nvidia-smi -pl" takes roughly a second per GPU, so applying the limits
# serially adds ~8 s to the prolog of every full-node job on an 8-GPU node.
# Apply them in parallel and collect the exit status of each child.
pids=()
for i in "${!limits[@]}"
do
    nvidia-smi -i "$i" -pl "${limits[$i]}" >/dev/null &
    pids+=("$!")
done

rc=0
for pid in "${pids[@]}"
do
    wait "$pid" || rc=1
done
exit "$rc"
