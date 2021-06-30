#!/bin/bash -l
#
# Test compiling and running an MPI program using NVIDIA HPC SDK

set -x
set -euo pipefail

module load nvhpc

mpicc -o "${HOME}/hello" "${HOME}/mpi-hello.c"

srun --mpi=pmix -n2 "${HOME}/hello"
