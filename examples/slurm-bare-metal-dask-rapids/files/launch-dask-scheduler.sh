#!/bin/bash

ANACONDA_ROOT="/usr/local/anaconda"
CONDA_ENV="/shared/conda"
export PATH="${CONDA_ENV}/bin:${ANACONDA_ROOT}/bin:${PATH}"

# shellcheck disable=SC1091
source activate "${CONDA_ENV}"

echo "Launching dask-scheduler on $(hostname)"
dask-scheduler --host "$(hostname)" || echo "Unable to start scheduler"
