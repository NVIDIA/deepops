# HPL Burn In Test

## Overview

This repository contains scripts and configuration files to use the GPU optimized version of HPL as a burnin test for GPU-based clusters.  The burnin test will repeatedly run HPL on different node counts to verify that each node, and each group of nodes, is providing the expected performance.  If a job runs slowly, it is an indicator that there is an issue with the node or network.  All nodes should perform equally.  

If the expected performance is seen, the user can be confident that the nodes are working correctly.  If a Top500 submittal is desired, there are additional optimizations than can done to maximize performance.  Please work with an NVIDIA Solutions Architect (SA) to review the Burn In Test results so that additional perfomance may be obtained.

Currently, only clusters built with DGX-1V-16GB, DGX-1V-32GB, DGX-2, and DGXA100 are supported.  If you have an OEM GPU-based system, contact your NVIDIA SA for additional assistance.

## Requirements

- This repository does not include the HPL binaries.  Contact your NVIDIA Solutions Architect or other NVIDIA representative for access.

## Getting started

Copy the DeepOps repo to the user's home directory of the slurm cluster to be tested. It is assumed that this directory is on a shared filed system. Place the hpl binary in the burn-in directory (`deepops/workloads/burn-in`) and run launch_experiment_slurm.sh.

```sh
git clone https://github.com/NVIDIA/deepops.git
cd deepops/workloads/burn-in/

```
> Note: All test scripts along with the HPL binary will be in this directory. It is referenced in code as `HPL_SCRIPTS_DIR`. The shared directory is referenced as `HPL_DIR`. These can both be changed by running `export HPL_DIR=<new_dir>; export HPL_SCRIPTS_DIR=<new_dir>`.

```
./launch_experiment_slurm.sh --sys <SYSTEM> --count <NODES_PER_JOBS> 

or

./launch_experiment_slurm.sh -s <SYSTEM> -c <NODES_PER_JOBS> 
```

   -s|--sys <SYSTEM>
        * Set to the system type on which to run.  Ex: dgx1v_16G, dgx1v_32G, dgx2, dgx2h, dgxa100, generic
    -c|--count <Count>
        * Set to the number of nodes to use per job


The script will lookup all of the available batch nodes on the system and launch a series of jobs on each.  

NOTE: For the Burn In Test, select the number of jobs (--count ) as 1 to run single node HPL on all available nodes within the cluster.

All results are written to a directory under the results subdirectory.  The launch script writes provides the location of that directory.  For example:

```
$ ./launch_experiment_slurm.sh -s dgx1v_16G -c 1

 GPU HPL Burnin Test
--------------------

NODELIST: prm-dgx-[03,05,09-20,25-26,28-36]

Experiment Variables:
EXPDIR: results/2node_dgx1v_16G_20200608104253
NITERS: 5
CUDA_VER: 10.1
PART: batch
SET_HCA_AFF: 0
MAXNODES: 1
MPIOPTS: 
TOTAL_NODES: 1
GRESSTR: --gpus-per-node=8
...
```

All the variables shown can be modified, but for the default case running from DeepOps, this should not be necessary.

At the end of each job, a result will be reported that says if the individual job passed or not.

## Verifying the results

Experiments are verified when all jobs are complete.  See the file verify_results.txt in the experiment directory.

## How to use these scripts to burn-in the cluster
 * Run an experiment where each node generates a result to identify any slow nodes.  If any slow nodes are found, fix them.

```
./launch_slurm_experiment.py -c 1 -s dgx1v_16G --maxnodes <number of nodes to run single node burn-in>
```
* Run multi-node jobs starting with two nodes, and increase them (four, eight, etc) until the size of the job to the next power of two would be greater than half the system.  At each node count, all runs should be completed successfully with similar performance.
*Run two jobs at N/2 in size (N is the total number of nodes). 
*Run a job with all nodes.


```
./launch_experiment_slurm.sh -c <number of nodes> -s <system type>

```
