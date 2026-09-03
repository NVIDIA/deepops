#!/usr/bin/env bash
set -e

case "$1" in
    default)
        nvidia-smi -rac           # Reset application clocks
        nvidia-smi -acp 0         # Reset application clock permissions
        nvidia-smi -c DEFAULT     # Reset compute mode to default
        ;;
    max)
        # Query every GPU in a single call, then apply in parallel:
        # "nvidia-smi -ac" also costs roughly a second per GPU.
        readarray -t maxSM  < <(nvidia-smi --query-gpu=clocks.max.sm  --format=csv,noheader,nounits)
        readarray -t maxMEM < <(nvidia-smi --query-gpu=clocks.max.mem --format=csv,noheader,nounits)
        pids=()
        for i in "${!maxSM[@]}" ; do
            nvidia-smi -i "${i}" -ac "${maxMEM[$i]}","${maxSM[$i]}" >/dev/null &
            pids+=("$!")
        done
        rc=0
        for pid in "${pids[@]}" ; do
            wait "$pid" || rc=1
        done
        exit "$rc"
        ;;
    *)
        echo "Usage: $0 [default|max]"
        exit 1
        ;;
esac
