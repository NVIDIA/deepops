Running a benchmark with RAPIDS and Dask with Slurm on bare metal
=================================================================

[RAPIDS](https://rapids.ai/) provides a suite of open source software libraries for doing data science on GPUs.
It's often used in conjunction with [Dask](https://dask.org/), a Python framework for running parallel computing jobs.
Both these tools can be used either in a containerized workflow, often using Kubernetes, or on "bare metal" with no containers, often using a shared HPC cluster.

In this example, we'll walk through running a simple RAPIDS-based benchmark using a bare-metal workflow, executed on a Slurm HPC cluster deployed using DeepOps.
The benchmark can be found in `examples/slurm-bare-metal-dask-rapids/sum.py`, and performs a parallel sum reduction test on either the CPUs or GPUs available to it.

The steps outlined below were tested using a virtual DeepOps cluster with one login node and two compute nodes,
where each compute node has been allocated 8 CPU cores and a single NVIDIA Tesla P4 GPU.
Any cluster hardware should work to duplicate this example, provided that each compute node you use for the benchmark includes at least one CUDA-capable GPU.

These steps assume that:

* You have already set up a Slurm cluster using the [Slurm deployment guide](/docs/slurm-cluster.md).
* All nodes in your cluster have access to a shared NFS filesystem (`/shared` below).
* You have privileges to run Ansible on this cluster.

1. From your DeepOps provisioning node, run the provided `prereqs.yml` Ansible playbook to ensure all system-level dependencies are present.
    ```
    $ ansible-playbook -l slurm-cluster -i <path_to_inventory_file> examples/slurm-bare-metal-dask-rapids/prereqs.yml
    ```
1. Log into your login node, and copy the files from this example to `/shared/benchmark`.
    ```
    $ hostname
    virtual-login
    $ ls /shared/benchmark
    
    ```
