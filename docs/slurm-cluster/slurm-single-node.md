# Single Node Slurm Deployment Guide

The general requirements and procedure for Slurm setup via deepops is documented
in the [README.md](README.md) for the slurm-cluster. The instructions below
outline the steps to deviate from the general setup to enable single node
DeepOps Slurm setup. The machine on which Slurm is being deployed should be
up to date in a stable state with GPU drivers already installed and functional.
The supported Operating Systems are Ubuntu (version 18 and 20), CentOS and RHEL
(version 7 and 8 albeit version 8 is preferred).

## Deployment Procedure

1. Clone the DeepOps repo.
    ```bash
    $ git clone https://github.com/NVIDIA/deepops.git
    $ cd deepops
    $ git checkout tags/<TAG>
    ```

2. Set up your provisioning machine.

    This will install Ansible and other prerequisite utilities for running deepops.
    ```
    $ ./scripts/setup.sh
    ```

3. Edit config and options.

    After running the setup script in step 2, a copy of “config.example”
    directory will be made to “config” directory. When one of the compute nodes
    also functions as a login node a few special configurations have to be set.

    a. Configuring inventory `"config/inventory"`.

    General configuration details can be found in the [configuration doc](../deepops/configuration.md).
    Let a host be named “gpu01” (example DGX-1 with 8 GPUs) with an ssh
    reachable ip address of “10.31.241.198”. If the deployment will be run
    locally on machine “gpu01” then ssh settings are optional. If the machine
    has a different hostname (i.e. not gpu01), then use the desired host name.
    Running the deployment will change the hostname to what is set in the
    inventory file. A single node config would look as follows:
    ```
    $ vi config/inventory
    [all]
    gpu01    ansible_host=10.31.241.198

    [slurm-master]
    gpu01

    [slurm-node]
    gpu01

    [all:vars]
    # SSH User
    ansible_user=dgxuser
    ansible_ssh_private_key_file='~/.ssh/id_rsa'
    ```

    If running deployment non-locally then depending on how the ssh is
    configured on the cluster one might have to generate a passwordless private
    key. Leave the password blank when prompted via command:
    ```bash
    $ ssh-keygen -t rsa
    ... accept defaults ...
    $ cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    $ chmod 600 ~/.ssh/authorized_keys
    ```

    Technicaly it is possible to setup a multinode Slurm with one of the compute
    nodes functioning as both a login and compute node. The config above just
    needs to list the additional nodes. Example:
    ```
    [all]
    gpu01     ansible_host=10.31.241.198
    gpu02     ansible_host=10.31.241.199

    [slurm-master]
    gpu01

    [slurm-node]
    gpu01
    gpu02
    ```

    b. Configuring `"config/group_vars/slurm-cluster.yml"`

    Typically users cannot ssh as local users directly to compute nodes in a
    Slurm cluster without a Slurm reservation. However, since in this
    deployment a compute node also functions as a login node we need to add
    users to slurm configuration for the ability to ssh as local users. Again,
    this is needed when a compute node also functions as a login node.
    Additionally, set the singularity install option (which is no by default).
    Singularity can be used to run containers and it will be used to set up
    rootless options as well. Do not set a default NFS with single node
    deployment.
    ```
    $ vi config/group_vars/slurm-cluster.yml
    slurm_enable_nfs_server: false
    slurm_enable_nfs_client_nodes: false
    slurm_cluster_install_singularity: yes

    slurm_login_on_compute: true

    slurm_allow_ssh_user:
    - "user1"
    - "user2"
    - "user3”
    ```

    The `slurm_login_on_compute` setting is to enable special settings on a
    compute node in order that it can function as a login node as well.

    Note: After deployment new users have to be manually added to “/etc/localusers”
    and “/etc/slurm/localusers.backup” on the node that functions as a login node.

4. Verify the configuration.

    Check that ansible can run successfully and reach hosts. Run the hostname
    utility on “all” the nodes. The “all” refers to the section in the
    `"config/inventory"` file.
    ```
    $ ansible all --connection=local -m raw -a "hostname"
    ```
    For non local setup do not set connection to local. This requires ssh config
    to be set up properly in the “`config/inventory`”.
    ```
    $ ansible all -m raw -a "hostname"
    ```

5. Install Slurm.

    When deploying on a single node set connection to local. Specify `"--forks=1"`
    so that Ansible does not perform potentially conflicting operations
    required for a slurm-master and slurm-node in parallel on the same node.
    The `"--forks=1"` option will insure that the installation steps are serial.
    ```
    $ ansible-playbook -K --forks=1 --connection=local -l slurm-cluster playbooks/slurm-cluster.yml
    ```
    For non-local installs do not set connection to local. The forks option is
    still required.
    ```
    # NOTE: If SSH requires a password, add: `-k`
    # NOTE: If sudo on remote machine requires a password, add: `-K`
    # NOTE: If SSH user is different than current user, add: `-u ubuntu`
    $ ansible-playbook -K --forks=1 -l slurm-cluster playbooks/slurm-cluster.yml
    ```

    During Slurm playbook reboot is usually done twice:

      * Once after installing the NVIDIA driver, because the driver sometimes
        requires a reboot to load correctly.
      * Once after setting some grub options used for Slurm compute nodes to
        configure cgroups correctly, because of modification to the kernel
        command line.

    The above reboot sequence cannot be automated when the compute and login
    node are on the same system. The recommended approach is to reboot manually
    when prompted and then run Ansible again.

    Setting `slurm_login_on_compute` to true, the slurm-cluster playbook will
    restrict GPUs in ssh sessions on the slurm-master by running the following
    command:
    ```
    $ sudo systemctl set-property sshd.service DeviceAllow="/dev/nvidiactl"
    ```
    Refer to `login-compute-setup.yml` role under `"roles/slurm/tasks"`. The
    reasoning for hiding GPUs in regular ssh sessions is that we want to
    avoid having users run a compute task on the GPUs without a Slurm job.

    If you desire to use docker within slurm then also install rootless docker
    after slurm deployment via playbook:
    ```
    $ ansible-playbook -K  --forks=1 --connection=local --limit slurm-cluster playbooks/container/docker-rootless.yml
    ```

6. Post install information.

    The admin users can access the GPUs that are restricted from regular ssh
    login sessions. This could be useful in situations when maybe GPU firmware
    needs to be updated. Let “dgxuser” be an admin user, they would access GPUs
    via command:
    ```
    login-session:$ nvidia-smi -L
    No devices found.

    login-session:$ sudo systemd-run --scope --uid=root --gid=root -- bash

    login-session-with-gpus:$ nvidia-smi -L | wc -l
    8
    ```
    Refer to official Slurm documentation for additional admin configurations
    and options. Typical Slurm options one might want to configure are time
    limits on jobs, accounts, qos settings, etcetera.


## Monitoring GPUs

Refer to DeepOps documentation regarding how monitoring is configured and
deployed on the Slurm cluster: [docs/slurm-cluster/slurm-monitor.md](./slurm-monitor.md)

The grafana dashboard will be available at the ip address of the manager node
on port 3000. Either open the url at the manager node's ip address or tunnel.
Example:
<http://10.31.241.198:3000>
```
$ ssh -L localhost:3000:localhost:3000 dgxuser@10.31.241.198

# open url:
http://127.0.0.1:3000/
```
On RHEL the grafana service might need to be exposed via `firewall-cmd`.
```
$ firewall-cmd --zone=public --add-port=3000/tcp --permanent
$ firewall-cmd --reload
```
If the monitoring is not working please check the running services:
```
$ systemctl list-units --state failed
```

## Logins and Running Jobs

After Slurm is deployed per above instructions the users can now request GPUs
and run containers. The following examples demonstrate the working pattern for a
multi-user team sharing a single DGX system (it would be similar with multiple
DGX systems just one of the systems functions as a login node as well).

### Initial SSH to Login Node

Let the ip address of the login system be “10.31.241.198” and user “testuser”.
They would ssh to the system as follows:
```
$ ssh testuser@10.31.241.198
testuser@10.31.241.198's password: 
Welcome to NVIDIA DGX Server Version 5.0.0 (GNU/Linux 5.4.0-52-generic x86_64)

  System information as of Wed 09 Dec 2020 10:16:09 PM UTC

  System load:  0.11                Processes:                 908
  Usage of /:   12.9% of 437.02GB   Users logged in:           2
  Memory usage: 1%                  IPv4 address for docker0:  172.17.0.1
  Swap usage:   0%                  IPv4 address for enp1s0f0: 10.31.241.198
  Temperature:  47.0 C

The system has 0 critical alerts and 5 warnings. Use 'sudo nvsm show alerts' for more details.

Last login: Tue Dec  1 00:01:32 2020 from 172.20.176.144
```

### Allocating GPUs

One suggestion is to add the following snippet or something similar to one's
`.bashrc`.
```
if [ ! -z "${SLURM_JOB_ID+x}" ]; then
    export PS1="slurm-${PS1}"
fi
```
The above will modify the prompt to indicate when one is within a Slurm session.
To request a GPU the testuser must first run a Slurm command with GPU allocation.
Example:
```
login-session:$ srun --ntasks=1 --cpus-per-task=5 --gpus-per-task=1 --pty bash

compute-session:$ nvidia-smi -L
GPU 0: Tesla P100-SXM2-16GB (UUID: GPU-61ba3c7e-584a-7eb4-d993-2d0b0a43b24f)
```
The job allocations details in Slurm can be viewed in another pane (such as one
of the tmux panes in the login session without GPU access) via “squeue” command
and details of the job can be viewed via “scontrol”.
```
login-session:$ squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON) 
               106     batch     bash testuser  R       3:34      1 gpu01

login-session:$ scontrol show jobid -dd 106
JobId=106 JobName=bash
   UserId=testuser(1002) GroupId=testuser(1002) MCS_label=N/A
   . . .
   NumNodes=1 NumCPUs=6 NumTasks=1 CPUs/Task=5 ReqB:S:C:T=0:0:*:*
   TRES=cpu=6,node=1,billing=6,gres/gpu=1
   Socks/Node=* NtasksPerN:B:S:C=0:0:*:1 CoreSpec=*
   JOB_GRES=gpu:1
     Nodes=gpu01 CPU_IDs=0-5 Mem=0 GRES=gpu:1(IDX:0)
   . . .
```
DeepOps deploys Slurm with “pam _slurm_adopt” such that ssh sessions are
permitted and adopted to allocated nodes. What that means is once a user has a
Slurm job, additional ssh sessions will be adopted to the job. Proceeding with
the above example let us assume that job 106 is running. If the testuser were
to make another ssh connection it would be adopted into (the latest if multiple
jobs) job.
```
$ ssh testuser@10.31.241.198
testuser@10.31.241.198's password: 
Welcome to NVIDIA DGX Server Version 5.0.0 (GNU/Linux 5.4.0-52-generic x86_64)
. . .
compute-session:$ echo NGPUS: $(nvidia-smi -L | wc -l) NCPUS: $(nproc)
NGPUS: 1 NCPUS: 6
```
Such ssh sessions are useful in various use cases (monitoring, debugging,
additional launch commands, etc.). These adopted ssh sessions are automatically
terminated when the corresponding Slurm job ends. The above scenario is also
why it is convenient to use tmux with the initial ssh session. One could even
attach to the tmux session in the adopted ssh session.

### Running Containers

DeepOps enables running containers with several containerization platforms:
docker, singularity, and enroot with pyxis.

#### Rootless Docker

Docker is currently the de facto standard for containerization. Docker is very
easy to work with when building and extending containers. NGC and many other
data science software stacks are distributed as docker containers. Fortunately,
it is straightforward to incorporate rootless docker with Slurm. The reason for
using rootless docker is that we want to avoid granting elevated privileges to
users unnecessarily.

DeepOps sets up rootless docker as a module package. Environment modules are a
popular way to setup cluster wide software for sharing. On a side note DeepOps
can set up easybuild or spack to manage environment modules and packages. The
workflow with rootless docker is as follows:

  1. A user starts a slurm job;
  2. module load the rootless docker package;
  3. Start rootless docker daemon;
  4. Work with docker containers per regular docker workflow.

The following examples will illustrate the commands. Start by reserving desired
resources:
```
login-session:$ srun --ntasks=1 --gpus-per-task=2 --pty bash
```
Load and start rootless docker:
```
compute-session:$ module load rootless-docker
compute-session:$ start_rootless_docker.sh
```
An option “--quiet” can be passed to the “start_rootless_docker.sh” script to
hide rootless docker messages. Pull/run a docker image:
```
compute-session:$ docker run --gpus=all --rm -it \
  deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
  mpirun --allow-run-as-root -np 2  all_reduce_perf -b 1M -e 4G -f 2 -g 1
```
This could be placed in a script and run with srun or sbatch. Example:
```
$ cat test-allreduce-docker.sh 
#!/bin/bash

module load rootless-docker

start_rootless_docker.sh --quiet

docker run --gpus=all --rm -t deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
  mpirun --allow-run-as-root -np 2  all_reduce_perf -b 1M -e 4G -f 2 -g 1

stop_rootless_docker.sh
```
Then run via:
```
login-session:$ srun --ntasks=1 --gpus-per-task=2 ${PWD}/test-allreduce-docker.sh
```
The Slurm constraints are enforced for rootless docker. This can be verified by
starting the container and checking the number of GPUs and CPUs available.
```
compute-session:$ docker run --gpus=all --rm -it \
  deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
  bash -c 'echo NGPUS: $(nvidia-smi -L | wc -l) NCPUS: $(nproc)'
NGPUS: 2 NCPUS: 2
```
It is important to be aware that rootless docker runs via user namespace
remapping. Therefore even though one might appear as root in a docker container,
files created are owned by the user, and within the container a user would not
have write/execute permissions to filesystem or executables that the user
already does not have permission to outside of the container.
```
compute-session:$ docker run --gpus=all --rm -it -v ${PWD}:${PWD} --workdir=${PWD} \
  deepops/nccl-tests-tf20.06-ubuntu18.04:latest bash -c 'touch somefile-in-container'
```
Then outside of the container.
```
$ ll -d somefile-in-container
-rw-r--r-- 1 testuser testuser 0 Dec 11 18:32 somefile-in-container

$ cat /etc/slurm/slurmdbd.conf
cat: /etc/slurm/slurmdbd.conf: Permission denied
```
Note there is no access to `slurmdbd.conf` within container since no access
outside of the container.
```
compute-session:$ docker run --gpus=all --rm -it -v /etc/slurm:/slurm --workdir=${PWD} \
  deepops/nccl-tests-tf20.06-ubuntu18.04:latest bash -c 'cat /slurm/slurmdbd.conf'
cat: /slurm/slurmdbd.conf: Permission denied
```
Rootless docker supports building containers and many standard docker features
with a few limitations. These limitations can make it challenging to run
multi node Slurm jobs, therefore for multi node jobs on Slurm the recommended
approach is via enroot or singularity.

A user can explicitly stop the rootless docker daemon with “stop_rootless_docker.sh”
script, or just exit the Slurm session. Upon exit from a slurm session the
processes in the session are killed therefore the user’s rootless docker
process will end.
```
compute-session:$ stop_rootless_docker.sh 
compute-session:$ exit
exit                                                
login-session:$
```
These scripts “start_rootless_docker.sh” and “stop_rootless_docker.sh” appear
on a user's path upon loading the rootless docker module.

### Enroot and Singularity

Singularity and enroot could  also be deployed via DeepOps. These would be
useful for multi-node jobs if running on more than one DGX system.
Enroot with pyxis can be tested by running:
```
login-session:$ srun --mpi=pmi2 --ntasks=2 --gpus-per-task=1 \
  --container-image=deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
  all_reduce_perf -b 1M -e 4G -f 2 -g 1
```
The pyxis+enroot is invoked via option “ --container-image=deepops/nccl-tests-tf20.06-ubuntu18.04:latest”
to run the “all_reduce_perf” nccl test. Refer to enroot and pyxis documentation
for further details.

Above, Slurm uses pmi2 to configure MPI. One does not need to call mpirun
explicitly. If one wanted to call mpirun directly then a launch script is
recommended. Example:
```
$ cat test-allreduce.sh
#!/bin/bash
if [ "$SLURM_PROCID" -eq "0" ]; then
mpirun all_reduce_perf -b 1M -e 4G -f 2 -g 1
fi
```
Then invoke as:
```
login-session:$ srun --ntasks=2 --gpus-per-task=1 --no-container-remap-root \
  --container-image=deepops/nccl-tests-tf20.06-ubuntu18.04:latest --container-workdir=${PWD} \
  test-allreduce.sh
```
The reason for `[ "$SLURM_PROCID" -eq "0" ]` is that srun and mpirun are redundant,
so you have to invoke either one or the other. That is “srun mpirun” will call
mpirun multiple times which is not what one wants. Note in the example script
“test-allreduce.sh” one does not have to pass any parameters to mpirun as these
will typically be inferred from the environment. Calling mpirun approach could
be useful, because certain binding options are not available to srun directly,
but can be set via mpirun.

Singularity could be used in a similar fashion to enroot. Don’t forget the
“--nv” option for GPUs.
```
login-session:$ srun --mpi=pmi2 --ntasks=2 --gpus-per-task=1 \
  singularity exec --nv docker://deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
    all_reduce_perf -b 1M -e 4G -f 2 -g 1
```
Similarly to invoke mpirun with singularity run script (same script as was used
with enroot):
```
login-session:$ srun --ntasks=2 --gpus-per-task=1 \
  singularity exec --nv docker://deepops/nccl-tests-tf20.06-ubuntu18.04:latest \
    ${PWD}/test_allreduce.sh
```
Refer to singularity documentation for further details. Building containers with
singularity is permitted to non-privileged users via the “--fakeroot” option.
Enroot and singularity excel at running containerized multi node jobs, which is
somewhat difficult and less convenient to do using docker on Slurm.
