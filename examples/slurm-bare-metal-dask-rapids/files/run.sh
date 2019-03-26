#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
pythonscript="${SCRIPT_DIR}/sum.py"

XDIM=500000
YDIM=500000

function usage {
    echo "usage: $pythonscript [-cgd]"
    echo "  -c use CPU only, num sockets, num cores"
    echo "  -g use local GPUs, number of GPUs"
    echo "  -d use distributed dask"
    exit 1
}

export MKL_NUM_THREADS=$(( $(nproc) / $(nvidia-smi -L | wc -l) ))

# Set MAX values
MAX_GPUS=$(nvidia-smi -L | wc -l)
MAX_CPU_SOCKETS=$(lscpu | grep Socket | awk '{print($NF)}')
MAX_CPU_CORES_PER_SOCKET=$(lscpu | grep -F "Core(s) per socket" | awk '{print($NF)}')
MAX_CPU_THREADS_PER_CORE=$(lscpu | grep Thread | awk '{print($NF)}')

DFLAG=0
CFLAG=0
GFLAG=0

while getopts ":c:g:x:y:d" opt; do
  case ${opt} in
        c)
            n_cores=${OPTARG}
            if [ "$n_cores" -gt $((MAX_CPU_CORES_PER_SOCKET * MAX_CPU_THREADS_PER_CORE)) ]; then
                n_cores=$((MAX_CPU_CORES_PER_SOCKET * MAX_CPU_THREADS_PER_CORE))
            fi
            CFLAG=1
            ;;
        g)
            n_gpus=${OPTARG}
            if [ "$n_gpus" -gt "$MAX_GPUS" ]; then
                n_gpus=$MAX_GPUS
            fi
            GFLAG=1
            ;;
        d)
            DFLAG=1
            ;;
        x)
            XDIM="${OPTARG}"
            ;;
        y)
            YDIM="${OPTARG}"
            ;;
        \?) echo "Usage: cmd [-c ncores] [-g ngpus] [-d]"
            ;;
        :)
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            ;;
  esac
done
shift $((OPTIND -1))

if [ $DFLAG == 1 ]; then
    if [ $GFLAG == 1 ] ; then
        python "$pythonscript" --use_distributed_dask --use_gpus_only --xdim="${XDIM}" --ydim="${YDIM}"
    elif [ $CFLAG == 1 ]; then
        python "$pythonscript" --use_distributed_dask --use_cpus_only --xdim="${XDIM}" --ydim="${YDIM}"
    fi
elif [ $GFLAG == 1 ]; then
    python "$pythonscript" --use_gpus_only --n_gpus="$n_gpus" --xdim="${XDIM}" --ydim="${YDIM}"
elif [ $CFLAG == 1 ]; then
    python "$pythonscript" --use_cpus_only --n_cpu_sockets="${MAX_CPU_SOCKETS}" --n_cpu_cores_per_socket="$n_cores" --xdim="${XDIM}" --ydim="${YDIM}"
fi
