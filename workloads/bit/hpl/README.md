# DeepOps Burn-In Test (BIT)

## Overview

This repository contains a set of scripts and configuration to burnin and validate the performance of DGX A100 clusters. The test will run a variety of containerized multi-node workloads (currently only HPL, NCCL is next).  The tests can also be run on generic GPU clusters, but specific configuration and interpretation of the results is left to the user.

The test are designed to be repeatedly run with different nodes and confirm that performance is consistent at each node count.  When tests run slowly or incorrectly, the nodes affected are reported.  Through continued system stress subtle and no-so-subtle hardware and system issues can be detected.  

If the expected performance is seen, the user can be confident that the nodes are working correctly.

## Differences between Burn-in and Validation
A validation test is to determine if the systems are performing as expected.  A burn-in test is 
repeated runs of the validation test to ensure systems continue to perform as expected over a 
period of time.  The tests described below are for system validation.  For a burn-in test, run 
validation tests back-to-back for an extended period of time.

## Requirements

- It is assumed that these tests are run under a DeepOps configured cluster with Slurm, Enroot, and Pyxis.
- A shared filesystem across all the compute nodes.

Note: Singularity should also work, but that code path has been minimally tested.

# High Performance Linpack (HPL)

## Getting started

Either copy, or just reclone, the DeepOps repository to a directory on a shared filesystem owned by the user (non-root) under which the tests will be run.

```
git clone https://github.com/NVIDIA/deepops.git
cd deepops/workloads/bit/hpl
```

## Setup Authentication to Access HPL container

The NGC HPC Benchmarks container is used to run HPL.  

https://ngc.nvidia.com/catalog/containers/nvidia:hpc-benchmarks

While the container is freely available, it is necessary to create an account on NGC to access the 
container.  After logging into NGC, you need to create an API key to pull containers. 

https://ngc.nvidia.com/setup

Follow the instructions there to create an API key.

###  To allow Enroot to access nvcr.io via the API key.

If not already created, create the file ~/.config/enroot/.credentials.  Add the following entries to that file:

```
machine nvcr.io login $oauthtoken password <NVCR.IO API KEY>
machine authn.nvidia.com login $oauthtoken password <NVCR.IO API KEY>
```
Replace <NVCR.IO API KEY> above with the your nvcr.io api key for your NGC account.

### Setup Authentication for Singularity nvcr.io

For Singularity, authentication to a docker registry is done through environment variables. 

```
export SINGULARITY_DOCKER_USERNAME='$oauthtoken'
export SINGULARITY_DOCKER_PASSWORD=<NGC_API_KEY>
```

Set these variables in the appropriate system config file (ex: syscfg-dgxa100-80gb.sh)


## Basic Launch Command

```
./launch_hpl_experiment.sh --sys <SYSTEM> --count <NODES_PER_JOBS> --cruntime enroot 

or

./launch_hpl_experiment.sh -s <SYSTEM> -c <NODES_PER_JOBS> --cruntime enroot
```

Where:

```
   -s|--sys <SYSTEM>
        * Set to the system type on which to run.  Ex: dgxa100_40G, dgxa100_80, generic
   -c|--count <Count>
        * Set to the number of nodes to use per job
   --container 
        * Specify an alternate continer URI or a local file (.sqsh for enroot, .sif for singularity)
   --cruntime <runtime> 
        * Specify the container runtime.  enroot is the only support runtime currently.
   -h|--help
        * Provide a full list of options
```

The script will lookup all of the available batch nodes on the system and launch a series of jobs on each.  More options exist to use BIT on non-standard systems.  Use the --help option for a full list of options.

NOTE: For the Burn In Test, select the number of jobs (--count ) as 1 to run single node HPL on all available nodes within the cluster.

All results are written to a directory under the results subdirectory.  The launch script writes provides the location of that directory.  For example:

```
$ ./launch_hpl_experiment.sh -s dgxa100_80G  -c 1 -i 5  --cruntime enroot

Using contaner runtime enroot

Experiment Variables:
HPL_DIR: /home/juser/deepops/workloads/bit/hpl
HPL_SCRIPTS_DIR: /home/juser/deepops/workloads/bit/hpl/
HPL EXPDIR: /home/juser/deepops/workloads/bit/hpl/results/1node_dgxa100_80G_20201215104946 system: dgxa100_80G
cruntime: enroot
CONT: /home/juser/deepops/workloads/bit/hpl/nvidia+hpc-benchmarks+20.10-hpl.sqsh
nodes_per_job: 1
gpus_per_node: 8
niters: 1
partition: admin
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

    Experiment Dir: /home/juser/deepops/workloads/bit/hpl/results/1node_dgxa100_80G_20201215104946
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
Experiment Results Directory: /home/juser/deepops/workloads/bit/hpl/results/1node_dgxa100_80G_20201215104946
Total Nodes: 5
Nodes Per Job:: 1
Verify Log: /home/juser/deepops/workloads/bit/hpl/results/1node_dgxa100_80G_20201215104946/verify_results.txt

To rerun the verification: /home/juser/deepops/workloads/bit/hpl/verify_hpl_experiment.py /home/juser/deepops/workloads/bit/results/1node_dgxa100_80G_20201215104946

```

All the variables shown can be modified, but for the default case running from DeepOps, this should not be necessary.

At the end of each job, a result will be reported that says if the individual job passed or not.

## Verifying the results

Experiments are verified when all jobs are complete.  See the file verify_results.txt in the experiment directory.

## How to use these scripts to burnn in the cluster
 * Run an experiment where each node generates a result to identify any slow nodes.  If any slow nodes are found, fix them.

```
./launch_hpl_experiment.py -c 1 -s dgxa100_80GG --maxnodes <maximum number of nodes to use>  --cruntime enroot
```
* Run multi-node jobs starting with two nodes, and increase them (four, eight, etc) until the size of the job to the next power of two would be greater than half the system.  At each node count, all runs should be completed successfully with similar performance.
*Run two jobs at N/2 in size (N is the total number of nodes). 
*Run a job with all nodes.


```
./launch_hpl_experiment.sh -c <number of nodes> -s <system type> --cruntime enroot

```

## Choosing the right system
Several different DGX system configurations are supported.  These include:

* DGX-1V 16GB    - syscfg-dgx1v-16gb.sh
* DGX-1V 32GB    - syscfg-dgx1v-32gb.sh
* DGX2           - syscfg-dgx2.sh
* DGX A100 40GB  - syscfg-dgxa100-40gb.sh
* DGX A100 80GB  - syscfg-dgxa100-80gb.sh

Note: The network topology of the DGX A100 40GB can vary depending on if you the node has the optional additional network card added.  Please edit the configuration file to match your node configuration.

