#!/bin/bash

ANACONDA_ROOT="/usr/local/anaconda"
CONDA_ENV="/shared/conda"
export PATH="${CONDA_ENV}/bin:${ANACONDA_ROOT}/bin:${PATH}"

# shellcheck disable=SC1091
source activate "${CONDA_ENV}"

export CUDA_ROOT=/usr/local/cuda
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_ROOT/lib64"
export NUMBAPRO_NVVM="$CUDA_ROOT/nvvm/lib64/libnvvm.so"
export NUMBAPRO_LIBDEVICE="$CUDA_ROOT/nvvm/libdevice"

echo "Launching dask-cuda-worker with scheduler $1 and port $2"
dask-cuda-worker "$1:$2" || echo "Unable to start worker"
