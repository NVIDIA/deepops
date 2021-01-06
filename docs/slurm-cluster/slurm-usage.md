Slurm Usage Guide
===

## Introduction

Slurm is an open-source job scheduling system for Linux clusters, most frequently used for high-performance computing (HPC) applications. This guide will cover some of the basics to get started using slurm as a user. For more information, the [Slurm Docs](https://slurm.schedmd.com/documentation.html) are a good place to start.

After [slurm is deployed on a cluster](./README.md), a slurmd daemon should be running on each compute system. Users do not log directly into each compute system to do their work. Instead, they execute slurm commands (ex: srun, sinfo, scancel, scontrol, etc) from a slurm login node. These commands communicate with the slurmd daemons on each host to perform work.

## Simple Commands

### Cluster state with sinfo

To "see" the cluster, ssh to the slurm login node for your cluster and run the `sinfo` command:

```sh
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
batch*       up   infinite      9   idle dgx[1-9]
```

There are 9 nodes available on this system, all in an `idle` state. If a node is busy, its state will change from `idle` to `alloc`:

```sh
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
batch*       up   infinite      1  alloc dgx1
batch*       up   infinite      8   idle dgx[2-9]
```

The `sinfo` command can be used to output a lot more information about the cluster. Check out the [sinfo doc for more](https://slurm.schedmd.com/sinfo.html).

### Running a job with srun

To run a job, use the `srun` command:

```sh
$ srun hostname
dgx1
```

What happened here? With the `srun` command we instructed slurm to find the first available node and run `hostname` on it. It returned the result in our command prompt. It's just as easy to run a different command that runs a python script or a container using srun.

Most of the time, scheduling on a full system is not necessary and it's better to request only a certain portion of the GPUs:

```sh
$ srun --gres=gpu:2 env | grep CUDA
CUDA_VISIBLE_DEVICES=0,1
```

Or, conversely, sometimes it's necessary to run on multiple systems:

```sh
$ srun --ntasks 2 -l hostname
dgx1
dgx2
```

### Running an interactive job

Especially when developing and experimenting, it's helpful to run an interactive job, which requests a resource and provides a command prompt as an interface to it:

```sh
slurm-login:~$ srun --pty /bin/bash
dgx1:~$ hostname
dgx
dgx1:~$ exit
```

During interactive mode, the resource is being reserved for use until the prompt is exited (as shown above). Commands can be run in succession.

> Note: before starting an interactive session with srun it may be helpful to create a session on the login node with a tool like tmux or `screen`. This will prevent a user from losing interactive jobs if there is a network outage or the terminal is closed.

## More Advanced Use

### Run a batch job

While the `srun` command blocks any other execution in the terminal, `sbatch` can be run to queue a job for execution once resources are available in the cluster. Also, a batch job will let you queue up several jobs that run as nodes become available. It's therefore good practice to encapsulate everything that needs to be run into a script and then execute with `sbatch` vs with `srun`:

```sh
$ cat script.sh
#!/bin/bash
/bin/hostname
sleep 30
$ sbatch script.sh
```

### Observing running jobs with squeue

To see which jobs are running in the cluster, use the `squeue` command:

```sh
$ squeue -a -l
Tue Nov 17 19:08:18 2020
JOBID PARTITION     NAME     USER    STATE       TIME TIME_LIMI  NODES NODELIST(REASON)
9     batch         bash   user01  RUNNING       5:43 UNLIMITED      1 dgx1
```

To see just the running jobs for a particulare user `USERNAME`:

```sh
$ squeue -l -u USERNAME
```

### Cancel a job with scancel

To cancel a job, use the `squeue` command to look up the JOBID and the `scancel` command to cancel it:

```sh
$ squeue
$ scancel JOBID
```

### Running an MPI job

To run a deep learning job with multiple processes, use MPI:

```sh
$ srun -p PARTITION --pty /bin/bash
$ singularity pull docker://nvcr.io/nvidia/tensorflow:19.05-py3
$ singularity run docker://nvcr.io/nvidia/tensorflow:19.05-py3
$ cd /opt/tensorflow/nvidia-examples/cnn/
$ mpiexec --allow-run-as-root -np 2 python resnet.py --layers=50 --batch_size=32 --precision=fp16 --num_iter=50
```

## Additional Resources

* [SchedMD Slurm Quickstart Guide](https://slurm.schedmd.com/quickstart.html)
* [LLNL Slurm Quickstart Guide](https://hpc.llnl.gov/banks-jobs/running-jobs/slurm-quick-start-guide)
