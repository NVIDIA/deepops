#!/usr/bin/env bash
set -e

gpu_count="$(nvidia-smi -L | wc -l)"

for i in $(seq 0 "$(( gpu_count - 1 ))" )
do
    case "$1" in
        max)
            next="$(nvidia-smi -i "$i" --query-gpu=power.max_limit --format=csv,noheader,nounits)"
            ;;
        default)
            next="$(nvidia-smi -i "$i" --query-gpu=power.default_limit --format=csv,noheader,nounits)"
            ;;
        min)
            next="$(nvidia-smi -i "$i" --query-gpu=power.min_limit --format=csv,noheader,nounits)"
            ;;
        *)
            echo "Usage: $0 [max,default,min]"
            exit 1
            ;;
    esac
    nvidia-smi -i "$i" -pl "$next"
done
