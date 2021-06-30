# Example scripts for Slurm prolog / epilog

This is a collection of scripts that could be added to a Slurm prolog / epilog.
These are not intended to be "drop in" solutions.  These scripts will need to be modified to fit various system configurations. 

## DCGM Stats
 - prolog-dcgmstats
 - epilog-dcgmstats

DCGM utilies must be installed.  https://developer.nvidia.com/data-center-gpu-manager-dcgm


These two scripts will collect GPU stats during a job.
nv-hostengine and dcgmi are executed as the user running the job.

The collected stats will be written to the job output dir. One file per host.

## ECC
 - prolog-ecc
 - epilog-ecc

These two scripts will disable ECC if requested by the user.  The user
makes this request by adding --comment=ecc to their job submission.

## MPS
 - prolog-mps
 - prolog-mps-per-gpu
 - epilog-mps

These scripts will start (and stop) the mps server if requested by the user.
The prolog-mps script will, if the user passes --comment=mps, start a single MPS
daemon on the node.  
The prolog-mps-per-gpu will, if the user passes --comment=mps-per-gpu, start one
MPS daemon and MPS server per GPU.  The MPS server will be bound to the appropriate
CPU cores. 

## DCGM Health Checks
 - prolog-dcgmhealth

DCGM utilies must be installed.  https://developer.nvidia.com/data-center-gpu-manager-dcgm


This script will run a quick (few seconds) health check of the GPUs on a node.  If the health check fails it will put the node into a drain state. Output from the health check will be written to /tmp/dcgm.out on the compute nodes.
**The job will fail and depending upon the slurm configuration it may or may not be requeued.  An interactive job will fail and not be requeued.**

The contents of /tmp/dcgm.out should look like:
```sh
Successfully ran diagnostic for group.
+---------------------------+------------------------------------------------+
| Diagnostic                | Result                                         |
+===========================+================================================+
|-----  Deployment  --------+------------------------------------------------|
| Blacklist                 | Pass                                           |
| NVML Library              | Pass                                           |
| CUDA Main Library         | Pass                                           |
| Permissions and OS Blocks | Pass                                           |
| Persistence Mode          | Pass                                           |
| Environment Variables     | Pass                                           |
| Page Retirement           | Pass                                           |
| Graphics Processes        | Pass                                           |
| Inforom                   | Pass                                           |
```

A failed health check might look like:
```sh
Successfully ran diagnostic for group.
+---------------------------+------------------------------------------------+
| Diagnostic                | Result                                         |
+===========================+================================================+
|-----  Deployment  --------+------------------------------------------------|
| Blacklist                 | Pass                                           |
| NVML Library              | Pass                                           |
| CUDA Main Library         | Pass                                           |
| Permissions and OS Blocks | Pass                                           |
| Persistence Mode          | Fail                                           |
| Environment Variables     | Fail                                           |
| Page Retirement           | Fail                                           |
| Graphics Processes        | Fail                                           |
| Inforom                   | Fail                                           |
+-----  Hardware  ----------+------------------------------------------------+
+-----  Integration  -------+------------------------------------------------+
+-----  Stress  ------------+------------------------------------------------+
+---------------------------+------------------------------------------------+
```

## GPU Reset
 - prolog-gpureset

This script will reset the application clocks on the GPUs, activate accounting, and clear the current logs. 
Inside this script there is a section that is commented out.  That commented out section would execute a 
reset of the gpu.  That is an action is is not always guaranteed to succeed and should be done with caution. 

## GPU Check
 - prolog-lspci

This script will check that lspci sees all the GPUs that a node should have according to Slurm.
**This script requires that slurm be configured with GPUs as a consumable resource (gres).  If this check fails the node will be put into a drain state. The job will fail and depending upon the slurm configuration it may or may not
 be requeued.  An interactive job will fail and not be requeued.**
 
## General cleanup
  - epilog-cleanup
 
This script will run some non-gpu specific cleanup tasks.  Kill user processes, sync cached writes, and drop caches.
It will also check for processes running on the GPUs.  If processes are found it will send them SIGKILL.
**If the processes are still running after 5 seconds the node will be drained.**

