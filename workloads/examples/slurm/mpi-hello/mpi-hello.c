#include <mpi.h>
#include <unistd.h>
#include <stdio.h>

int main(int argc, char **argv) {
    // Initialize MPI
    MPI_Init(&argc, &argv);

    // Get the number of processes in the global communicator
    int count;
    MPI_Comm_size(MPI_COMM_WORLD, &count);

    // Get the rank of the current process
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    // Get the current hostname
    char hostname[1024];
    gethostname(hostname, sizeof(hostname));

    // Print a hello world message for this rank
    printf("Hello from process %d of %d on host %s\n", rank, count, hostname);

    // Finalize the MPI environment before exiting
    MPI_Finalize();
}
