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
        #
        # Index, memory clock and SM clock come from one query so the three
        # values of a GPU cannot drift out of alignment. Reading them through
        # "readarray -t maxSM < <(nvidia-smi ...)" hid the query's exit status
        # from both readarray and "set -e": a failed query left the arrays
        # empty and the helper exited 0 having set nothing, and two separate
        # queries returning different row counts made "${maxMEM[$i]}" empty for
        # the trailing GPUs, producing an "-ac ,1980" argument.
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT

        if ! nvidia-smi --query-gpu=index,clocks.max.mem,clocks.max.sm \
                        --format=csv,noheader,nounits > "$tmp"; then
            echo "$0: querying the maximum clocks failed" >&2
            exit 1
        fi

        # Every GPU that nvidia-smi lists has to be present in the query
        # result before anything is written. The listing is captured on its
        # own: in "$(nvidia-smi -L | grep -c ...)" the status belongs to
        # grep, so a partial listing followed by a nonzero nvidia-smi exit
        # counted the rows it did emit and passed validation.
        if ! gpu_list=$(nvidia-smi -L); then
            echo "$0: could not list the GPUs" >&2
            exit 1
        fi
        expected=$(printf '%s\n' "$gpu_list" | grep -c '^GPU ') || expected=0
        if [ "$expected" -eq 0 ]; then
            echo "$0: nvidia-smi -L reported no GPUs" >&2
            exit 1
        fi

        # Rows are counted as they are read rather than with bash's
        # array-length expansion. These files are installed with the template
        # module, and the brace-hash sequence that expansion needs opens a
        # Jinja comment, so the render fails with "Missing end of comment tag"
        # before the script can run.
        rows=0
        indexes=()
        maxMEM=()
        maxSM=()
        while IFS=', ' read -r index mem sm _; do
            [ -z "$index" ] && continue
            if ! [[ "$index" =~ ^[0-9]+$ ]] \
               || ! [[ "$mem" =~ ^[0-9]+$ ]] \
               || ! [[ "$sm" =~ ^[0-9]+$ ]]; then
                echo "$0: unexpected row from nvidia-smi: '$index, $mem, $sm'" >&2
                exit 1
            fi
            indexes+=("$index")
            maxMEM+=("$mem")
            maxSM+=("$sm")
            rows=$((rows + 1))
        done < "$tmp"

        if [ "$rows" -ne "$expected" ]; then
            echo "$0: got $rows usable clock rows, expected $expected" >&2
            exit 1
        fi

        pids=()
        for i in "${!indexes[@]}" ; do
            nvidia-smi -i "${indexes[$i]}" -ac "${maxMEM[$i]}","${maxSM[$i]}" >/dev/null &
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
