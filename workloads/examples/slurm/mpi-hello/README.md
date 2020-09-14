"Hello, World" with MPI on a Slurm cluster
==========================================

Slurm is an open-source job scheduling system for Linux clusters, most frequently used for high-performance computing (HPC) applications.
Many HPC applications are built on the Message Passing Interface (MPI) standard, which allows multiple processes in an application to communicate across nodes.

This example demonstrates how to build and run simple "hello, world" MPI application on a Slurm cluster.
It assumes that you have already deployed a cluster with a login node and at least one compute node, and that Slurm has already been set up and configured.
It also assumes the presence of a shared NFS filesystem on all nodes in the cluster, which is given the path `/shared` in this example.
If you haven't configured a Slurm cluster yet, see the [Slurm guide](/docs/slurm-cluster.md) for information on building a GPU-enabled Slurm cluster.

1. **Install the OpenMPI packages:**
    On many clusters, MPI libraries and tools are built from source to take advantage of the specific cluster hardware.
    In this example, we'll just use the OpenMPI provided by Ubuntu to demonstrate running an MPI job.
    To install OpenMPI, run the `bootstrap-mpi.yml` Ansible playbook in this directory. 
    If you only want to install on a subset of nodes, use the `-l ${HOST_GROUP}` argument to restrict where this playbook is run.
    ```
    $ ansible-playbook -i ${INVENTORY_FILE} [-l ${HOST_GROUP}] examples/slurm/mpi-hello/bootstrap-mpi.yml
    ```
1. Upload the source code and job script to the shared filesystem on your login node:
    ```
    $ scp examples/slurm/mpi-hello/mpi-hello.c login:/shared/
    ```
1. Log into your cluster and build the MPI application.
    ```
    $ ssh login
    $ cd /shared
    $ mpicc -o mpi-hello mpi-hello.c
    ```
1. One way to run Slurm jobs is in "interactive" mode, where you get a resource allocation and then launch processes by hand.
    To run our hello app interactively, you can do the following:

    ```
    # Validate that we're on the login node
    $ hostname
    login

    # Allocate two processors from Slurm
    # (in this case, both processors are on the same node)
    $ salloc -n 2
    salloc: Granted job allocation 7

    # Run the MPI application using mpirun
    $ mpirun -np 2 /shared/mpi-hello
    Hello from process 0 of 2 on host virtual-gpu01
    Hello from process 1 of 2 on host virtual-gpu01

    # Release the allocation
    $ exit
    exit
    salloc: Relinquishing job allocation 7
    salloc: Job allocation 7 has been revoked.
    ```
1. The other way to run a Slurm job is using a batch script.
    This is just a shell script which contains the commands needed to run your app,
    as well as comments prefixed `#SBATCH` which tell Slurm about the job you're running.
    The output of your job is saved to a file.
    ```
    $ cat hello-job.sh
    #!/bin/bash
    #SBATCH -J mpi-hello            # Job name
    #SBATCH -n 2                    # Number of processes
    #SBATCH -t 0:10:00              # Max wall time
    #SBATCH -o hello-job.out        # Output file name
    
    # Disable the Infiniband transport for OpenMPI (not present on all clusters)
    export OMPI_MCA_btl="^openib"
    
    # Run the job (assumes the batch script is submitted from the same directory)
    mpirun -np 2 ./mpi-hello
    
    $ sbatch hello-job.sh
    Submitted batch job 9
    $ cat hello-job.out
    Hello from process 0 of 2 on host virtual-gpu01
    Hello from process 1 of 2 on host virtual-gpu01
    ```

To learn more about how to use Slurm, see the [Slurm user documentation](https://slurm.schedmd.com/documentation.html).
