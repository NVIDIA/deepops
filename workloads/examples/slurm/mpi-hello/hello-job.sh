#!/bin/bash
#SBATCH -J mpi-hello            # Job name
#SBATCH -n 2                    # Number of processes
#SBATCH -t 0:10:00              # Max wall time
#SBATCH -o hello-job.out        # Output file name

# Disable the Infiniband transport for OpenMPI (not present on all clusters)
export OMPI_MCA_btl="^openib"

# Run the job (assumes the batch script is submitted from the same directory)
mpirun -np 2 ./mpi-hello
