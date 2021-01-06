Running a benchmark with RAPIDS and Dask with Slurm on bare metal
=================================================================

[RAPIDS](https://rapids.ai/) provides a suite of open source software libraries for doing data science on GPUs.
It's often used in conjunction with [Dask](https://dask.org/), a Python framework for running parallel computing jobs.
Both these tools can be used either in a containerized workflow, often using Kubernetes, or on "bare metal" with no containers, often using a shared HPC cluster.

In this example, I'll walk through running a simple RAPIDS-based benchmark using a bare-metal workflow, executed on a Slurm HPC cluster deployed using DeepOps.
The steps outlined below were tested using a virtual DeepOps cluster with one login node and two compute nodes,
where each compute node has been allocated 8 CPU cores and a single NVIDIA Tesla P4 GPU.
Any cluster hardware should work to duplicate this example, provided that each compute node you use for the benchmark includes at least one CUDA-capable GPU.

## Assumptions

These instructions assume that:

* You have already set up a Slurm cluster using DeepOps.
    * If you haven't configured a cluster yet, see the [Slurm deployment guide](/docs/slurm-cluster.md) for deploying on physical hardware, or the [virtual guide](/virtual/README.md) to set up a virtual DeepOps cluster.
* You have privileges to run Ansible on this cluster.
    * If you don't have these privileges, talk to your system administrator to see if they can set up the system dependencies. The only system dependencies for this example are captured in the Ansible playbook, `examples/slurm/dask-rapids/ansible-prereqs.yml`.
* All compute nodes in your cluster have at least one CUDA-capable GPU.
* All nodes (compute and login) in your cluster have access to a shared NFS filesystem.
    * In many clusters `/home` is shared for easy use by users, but we will use `/shared` below to make the use of this filesystem explicit. If your path is different, just adjust the commands below as needed.
* The user you will use to run jobs has passwordless SSH access from your login node to the compute nodes.

## Install software dependencies and prepare your environment

1. From your DeepOps provisioning node, run the provided `ansible-prereqs.yml` Ansible playbook to ensure all system-level dependencies are present.
    This playbook will also copy the scripts from this directory to `/usr/share/deepops`.
    ```
    $ ansible-playbook -l slurm-cluster -i <path_to_inventory_file> examples/slurm/dask-rapids/ansible-prereqs.yml
    ```
1. To install Dask, Rapids, and supporting libraries, I'll create a custom Python environment using the [Anaconda Python Distribution](https://www.anaconda.com/distribution/). I'll install this environment in the NFS filesystem (`/shared`) to make it visible to all the compute nodes.
    ```
    $ hostname
    virtual-login
    $ /usr/local/anaconda/bin/conda env create --prefix /shared/conda -f /usr/share/deepops/conda-requirements.yml
    ```
1. Source the Anaconda environment and install extra dependencies.
    ```
    $ source /usr/local/anaconda/bin/activate /shared/conda
    $ pip install git+https://github.com/rapidsai/dask-xgboost@dask-cudf
    $ pip install git+https://github.com/rapidsai/dask-cuda@main
    ```
1. Make a `/shared/benchmark` directory for working files while we run.
    ```
    $ mkdir /shared/benchmark
    $ cd /shared/benchmark
    ```

### Make sure you have SSH access to nodes in a Slurm job

The instructions below assume that you have SSH access from the login node to compute nodes in your Slurm jobs.
To test this, start a single-node job and try to SSH:

```
[vagrant@virtual-login ~]$ salloc -N 1
salloc: Granted job allocation 4
[vagrant@virtual-login ~]$ squeue -j 4
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 4     batch     bash  vagrant  R       0:05      1 virtual-gpu01
[vagrant@virtual-login ~]$ ssh virtual-gpu01
Last login: Fri Mar 22 18:56:58 2019 from 10.0.0.4
[vagrant@virtual-gpu01 ~]$
```

If this doesn't work, work with your local system administrator to configure this access.

If you are running this example using the DeepOps [Virtual Cluster](/virtual/README.md) with the default Vagrant config, you can use SSH agent forwarding from your VM host to ensure this access is present.
For example:

```
ubuntu@ivb120:~$ eval `ssh-agent`
Agent pid 21594
ubuntu@ivb120:~$ ssh-add
Identity added: /home/ubuntu/.ssh/id_rsa (/home/ubuntu/.ssh/id_rsa)
ubuntu@ivb120:~$ ssh -A vagrant@virtual-login
The authenticity of host 'virtual-login (10.0.0.4)' can't be established.
ECDSA key fingerprint is SHA256:mhLsw3s1KUUMPSHaPSq+JdEqVcxywJATrBpTIohR3Es.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added 'virtual-login,10.0.0.4' (ECDSA) to the list of known hosts.
Last login: Fri Mar 22 18:56:00 2019 from 10.0.0.1
[vagrant@virtual-login ~]$ ssh virtual-gpu01
Last login: Fri Mar 22 18:41:51 2019 from 10.0.0.4
[vagrant@virtual-gpu01 ~]$
```

## Setting up your Dask job

1. Allocate compute nodes for a Slurm interactive job to run the benchmark. In this case we'll use two compute nodes. Note the job allocation number after running `salloc`.
    ```
    vagrant@virtual-login:/shared/benchmark$ salloc -N 2  # where 2 is the number of nodes
    salloc: Granted job allocation 6
    vagrant@virtual-login:/shared/benchmark$ squeue -j 6  # where 6 is the job id
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 6     batch     bash  vagrant  R       2:52      2 virtual-gpu[01-02]
    ```
1. If not already done, source the Anaconda environment.
    ```
    vagrant@virtual-login:/shared/benchmark$ source /usr/local/anaconda/bin/activate /shared/conda
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$
    ```
1. Launch the Dask scheduler on the first compute node. Note the IP and port for the scheduler process.
    ```
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ ssh virtual-gpu01 /usr/share/deepops/launch-dask-scheduler.sh &
    [1] 32563
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ Launching dask-scheduler on virtual-gpu01
    distributed.scheduler - INFO - -----------------------------------------------
    distributed.scheduler - INFO - Clear task state
    distributed.scheduler - INFO -   Scheduler at:      tcp://10.0.0.11:8786
    distributed.scheduler - INFO -       bokeh at:            10.0.0.11:8787
    distributed.scheduler - INFO - Local Directory:    /tmp/scheduler-3darpfr_
    distributed.scheduler - INFO - -----------------------------------------------
    ```
1. Launch Dask CUDA workers on each of the compute nodes. Pass the script the IP address and port of the scheduler.
    ```
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ ssh virtual-gpu01 /usr/share/deepops/launch-dask-cuda-worker.sh 10.0.0.11 8786 &
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ ssh virtual-gpu02 /usr/share/deepops/launch-dask-cuda-worker.sh 10.0.0.11 8786 &
    ```

## Run the GPU benchmark

1. Use Slurm to get an interactive login with your job environment on a compute node.
    ```
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ srun -n1 --pty -- /bin/bash
    srun: Warning: can't run 1 processes on 2 nodes, setting nnodes to 1
    vagrant@virtual-gpu01:/shared/benchmark$
    ```
1. Run the benchmark on a single GPU (not running in distributed mode)
    ```
    vagrant@virtual-gpu01:/shared/benchmark$ /usr/share/deepops/run.sh -g 1
    Using GPUs and Local Dask
    Port 8787 is already in use.
    Perhaps you already have a cluster running?
    Hosting the diagnostics dashboard on a random port instead.
    Allocating and initializing arrays using GPU memory with CuPY
    Array size: 2.00 TB.  Computing parallel sum . . .
    Processing complete.
    Wall time create data + computation time: 254.01085186 seconds
    ```
1. Run the benchmark on all compute node GPUs (distributed mode)
    ```
    vagrant@virtual-gpu01:/shared/benchmark$ /usr/share/deepops/run.sh -g 1 -d
    Using Distributed Dask
    Allocating and initializing arrays using GPU memory with CuPY
    Array size: 2.00 TB.  Computing parallel sum . . .
    Processing complete.
    Wall time create data + computation time: 128.67964649 seconds
    ```
1. Clean up.
    ```
    vagrant@virtual-gpu01:/shared/benchmark$ killall dask-cuda-worker
    vagrant@virtual-gpu01:/shared/benchmark$ killall dask-scheduler
    vagrant@virtual-gpu01:/shared/benchmark$ exit
    exit
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ ssh virtual-gpu02 killall dask-cuda-worker
    (/shared/conda) vagrant@virtual-login:/shared/benchmark$ exit
    exit
    salloc: Relinquishing job allocation 6
    vagrant@virtual-login:/shared/benchmark$
    ```
