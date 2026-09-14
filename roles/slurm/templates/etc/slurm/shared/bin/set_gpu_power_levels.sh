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
#
# The result is written to a file rather than read through
# "readarray -t limits < <(nvidia-smi ...)": inside a process substitution the
# query's exit status is invisible to both readarray and "set -e", so a failed
# query left the array empty, the write loop ran zero times, and the helper
# still exited 0 having configured nothing. A truncated result configured only
# some of the GPUs and also returned success.
#
# The index is queried alongside the value so each write targets the GPU that
# nvidia-smi actually reported, rather than assuming the array subscript equals
# the GPU index.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if ! nvidia-smi --query-gpu=index,"$query" --format=csv,noheader,nounits > "$tmp"; then
    echo "$0: querying $query failed" >&2
    exit 1
fi

# Every GPU that nvidia-smi lists has to be present in the query result before
# anything is written. The listing is captured on its own: in
# "$(nvidia-smi -L | grep -c ...)" the status belongs to grep, so a partial
# listing followed by a nonzero nvidia-smi exit counted the rows it did emit
# and passed validation.
if ! gpu_list=$(nvidia-smi -L); then
    echo "$0: could not list the GPUs" >&2
    exit 1
fi
expected=$(printf '%s\n' "$gpu_list" | grep -c '^GPU ') || expected=0
if [ "$expected" -eq 0 ]; then
    echo "$0: nvidia-smi -L reported no GPUs" >&2
    exit 1
fi

# Rows are counted as they are read rather than with bash's array-length
# expansion. These files are installed with the template module, and the
# brace-hash sequence that expansion needs opens a Jinja comment, so the
# render fails with "Missing end of comment tag" before the script can run.
rows=0
indexes=()
limits=()
while IFS=', ' read -r index limit _; do
    [ -z "$index" ] && continue
    if ! [[ "$index" =~ ^[0-9]+$ ]] || ! [[ "$limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$0: unexpected row from nvidia-smi: '$index, $limit'" >&2
        exit 1
    fi
    indexes+=("$index")
    limits+=("$limit")
    rows=$((rows + 1))
done < "$tmp"

if [ "$rows" -ne "$expected" ]; then
    echo "$0: got $rows usable rows for $query, expected $expected" >&2
    exit 1
fi

# "nvidia-smi -pl" takes roughly a second per GPU, so applying the limits
# serially adds ~8 s to the prolog of every full-node job on an 8-GPU node.
# Apply them in parallel and collect the exit status of each child.
pids=()
for i in "${!indexes[@]}"
do
    nvidia-smi -i "${indexes[$i]}" -pl "${limits[$i]}" >/dev/null &
    pids+=("$!")
done

rc=0
for pid in "${pids[@]}"
do
    wait "$pid" || rc=1
done
exit "$rc"
