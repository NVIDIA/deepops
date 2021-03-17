# DeepOps Burn-In Test

## Overview

This repository contains a set of scripts to validate the performance of DGX A100 clusters. The test will run a variety of multi-node workloads (currently only HPL, NCCL is next).  The tests can also be run on generic GPU clusters, but interpretation of the results is left to the user.

The HPL burnin test will repeatedly run HPL on different node counts to verify that each node, and each group of nodes, is providing the expected performance.  If a job runs slowly, it is an indicator that there is an issue with the node or network.  All nodes should perform equally.  

If the expected performance is seen, the user can be confident that the nodes are working correctly.


### NCCL Overview
(This test is still a work in progress)

The NCCL test will use the NCCL all_reduce_perf test to validate fabric correctness and performance.  Testing has only been done on InfiniBand based fabrics. 

## Requirements

- These tests are container based. A working Slurm environment with Pyxis and Enroot is currently required.  There is a codepath for Singularity, but it has been minimally tested.

## Getting started

Copy the DeepOps repo to the user's home directory of the slurm cluster to be tested. It is assumed that this directory is on a shared filed system. Place the hpl binary in the burn-in directory (`deepops/workloads/burn-in`) and run launch_experiment_slurm.sh.

```sh
git clone https://github.com/NVIDIA/deepops.git
cd deepops/workloads/burn-in/

```

```
./launch_hpl_experiment.sh --sys <SYSTEM> --count <NODES_PER_JOBS> --container nvcr.io#nvidia/hpc-benchmarks:20.10-hpl --cruntime enroot

or

./launch_hpl_experiment.sh -s <SYSTEM> -c <NODES_PER_JOBS> --container nvcr.io#nvidia/hpc-benchmarks:20.10-hpl  --cruntime enroot
```

Where:

```
   -s|--sys <SYSTEM>
        * Set to the system type on which to run.  Ex: dgxa100_40G, dgxa100_80, generic
   -c|--count <Count>
        * Set to the number of nodes to use per job
   --container 
        * Specify a continer URI or a local file (.sqsh for enroot, .sif for singularity)
   --cruntime <runtime> 
        * Specify the container runtime.  enroot is the only support runtime currently.


The script will lookup all of the available batch nodes on the system and launch a series of jobs on each.  

NOTE: For the Burn In Test, select the number of jobs (--count ) as 1 to run single node HPL on all available nodes within the cluster.

All results are written to a directory under the results subdirectory.  The launch script writes provides the location of that directory.  For example:

```
$ ./launch_hpl_experiment.sh -s dgxa100_80G  -c 5 --container nvcr.io#nvidia/hpc-benchmarks:20.10-hpl  --cruntime enroot

Using contaner runtime enroot

Experiment Variables:
HPL_DIR: /home/juser/deepops/workloads/burn-in
HPL_SCRIPTS_DIR: /home/juser/deepops/workloads/burn-in
EXPDIR: /home/juser/deepops/workloads/burn-in/results/1node_dgxa100_80G_20201215104946
system: dgxa100_80G
cruntime: enroot
CONT: /home/juser/deepops/workloads/burn-in/nvidia+hpc-benchmarks+20.10-hpl.sqsh
nodes_per_job: 1
gpus_per_node: 8
gpuclock: <Not Set>
memclock: <Not Set>
niters: 1
partition: admin
usehca: 0
maxnodes: 5
mpiopts: <Not Set>
gresstr: <Not Set>
total_nodes: 5
hpldat: <Not Set>


....... LOGGING INFORMATINON"

====================
Experiment completed
====================

Verifying HPL Burnin Results


Issues Found:

No Issues Found


Summary:

    Experiment Dir: /home/juser/deepops/workloads/burn-in/results/1node_dgxa100_80G_20201215104946
        Total Jobs: 5
         Slow Jobs: 0
       Failed Jobs: 0
      Unknown Jobs: 0
  Did Not Complete: 0
           HPL CFG: WR01L8R2
                 N: 288000
                NB: 288
               P*Q: 4*2
          Hostlist: node-001:1,node-002:1,node-003:1,node-004:1,node-005:1
           MaxPerf: 109700.0 GF
           MinPerf: 108000.0 GF
     Percent Range: 1.55%


Run Summary:
Experiment Results Directory: /home/juser/deepops/workloads/burn-in/results/1node_dgxa100_80G_20201215104946
Total Nodes: 5
Nodes Per Job:: 1
Verify Log: /home/juser/deepops/workloads/burn-in/results/1node_dgxa100_80G_20201215104946/verify_results.txt

To rerun the verification: /home/juser/deepops/workloads/burn-in/verify_hpl_experiment.py /home/juser/deepops/workloads/burn-in/results/1node_dgxa100_80G_20201215104946

```

All the variables shown can be modified, but for the default case running from DeepOps, this should not be necessary.

At the end of each job, a result will be reported that says if the individual job passed or not.

## Verifying the results

Experiments are verified when all jobs are complete.  See the file verify_results.txt in the experiment directory.

## How to use these scripts to burn-in the cluster
 * Run an experiment where each node generates a result to identify any slow nodes.  If any slow nodes are found, fix them.

```
./launch_hpl_experiment.py -c 1 -s dgxa100_80GG --maxnodes <number of nodes to run single node burn-in> --container nvcr.io#nvidia/hpc-benchmarks:20.10-hpl  --cruntime enroot
```
* Run multi-node jobs starting with two nodes, and increase them (four, eight, etc) until the size of the job to the next power of two would be greater than half the system.  At each node count, all runs should be completed successfully with similar performance.
*Run two jobs at N/2 in size (N is the total number of nodes). 
*Run a job with all nodes.


```
./launch_hpl_experiment.sh -c <number of nodes> -s <system type>

```

## Using the test on generic systems

Todo
