#!/usr/bin/env bash
set -e

gpu_count="$(nvidia-smi -L | wc -l)"

case "$1" in
    default)
        nvidia-smi -rac           # Reset application clocks
        nvidia-smi -acp 0         # Reset application clock permissions
        nvidia-smi -c DEFAULT     # Reset compute mode to default
        ;;
    max)
        for i in $(seq 0 "$(( gpu_count - 1 ))" ) ; do
            nextSM="$(nvidia-smi -i "$i" --query-gpu=clocks.max.sm --format=csv,noheader,nounits)"
            nextMEM="$(nvidia-smi -i "$i" --query-gpu=clocks.max.mem --format=csv,noheader,nounits)"
            nvidia-smi -i "${i}" -ac "${nextMEM}","${nextSM}"
        done
        ;;
    *)
        echo "Usage: $0 [default|max]"
        exit 1
        ;;
esac
