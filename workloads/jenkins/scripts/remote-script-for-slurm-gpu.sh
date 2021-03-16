#!/bin/bash -l
#
# Test compiling and running a GPU program using NVIDIA HPC SDK

set -x
set -euo pipefail

module load nvhpc
nvcc -o "${HOME}/deviceQuery" -I /usr/local/cuda/samples/common/inc /usr/local/cuda/samples/1_Utilities/deviceQuery/deviceQuery.cpp
srun -n1 -G1 "${HOME}/deviceQuery"
