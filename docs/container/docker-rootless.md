# Rootless Docker

Rootless docker enables unprivileged end-users to utilize docker containers.
One motivation for this is that typically it is easier to manage unprivileged
users within HPC clusters such as SLURM. Alternatives, such as Singularity and
Enroot, also enable an unprivileged user to utilize containerization. The added
convenience of rootless docker is that if one is working with docker containers
it would be more straightforward to build and run docker containers instead of
having to convert to another container format.

Further information about rootless docker can be found here:
<https://docs.docker.com/engine/security/rootless/>


## Installing Rootless Docker

An ansible role and playbook are provided to install rootless docker
[docker-rootless.yml](../../playbooks/container/docker-rootless.yml).
The default install location is set via variable `rootlessdocker_install_dir`
with default setting of `/sw/software/rootless_docker`. Set the variable to a
different value (use `--extra-vars "rootlessdocker_install_dir=<somepath>"`) if
a different install location is desired. Run the playbook via ansible command:
```bash
ansible-playbook -K --limit slurm-cluster playbooks/container/docker-rootless.yml
```

For networking to properly work with rootless docker the `br_netfilter` kernel
module should be loaded. Check via:
```
$ lsmod | grep br_netfilter
```
The `br_netfilter` kernel module is typically installed by default on various
Linux platforms. If not loaded then load via:
```
$ sudo modprobe br_netfilter
# to load by default on bootup
$ sudo sh -c 'echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'
```

## Using Rootless Docker in Slurm

The playbook installs an environment module for loading rootless docker via
modules. Users with bash shells will see the following modules in a typical
DeepOps deployed Slurm cluster:
```
$ module avail

-------------------------------------------------------------------------- /sw/hpc-sdk/modulefiles ----------------------------------
   nvhpc/20.7    nvhpc/20.9 (D)    nvhpc-byo-compiler/20.7    nvhpc-byo-compiler/20.9 (D)    nvhpc-nompi/20.7    nvhpc-nompi/20.9 (D)

------------------------------------------------------------------ /sw/software/rootless-docker/modulefiles -------------------------
   rootless-docker

  Where:
   D:  Default Module
```

Once the rootless docker module is loaded scripts "start_rootless_docker.sh"
and "stop_rootless_docker.sh" will become available (added via PATH). Use
these scripts to start an stop rootless docker daemon. The commands below
illustrate how to start and run a rootless docker container on Slurm.
```
$ srun --ntasks=1 --gpus-per-task=1 --cpus-per-task=5 --gres-flags=enforce-binding --pty bash

$ module load rootless-docker

$ start_rootless_docker.sh # specify --quiet option to hide rootles docker messages

$ docker run --gpus all -it --rm nvcr.io/nvidia/cuda:11.0-base-ubuntu18.04

root@445bf5cca686:/# echo NGPUS: $(nvidia-smi -L | wc -l)
NGPUS: 1

root@445bf5cca686:/# exit # exit docker interactive sessions
exit

$ stop_rootless_docker.sh # Optionally explicitly stop rootless docker. Will be killed on Slurm exit regardless.

$ exit # end slurm session
exit

```

It is important to be aware that rootless docker runs via user namespace
remapping. Therefore even though one might appear as root in a docker
container, files created are owned by the user, and within the container a user
would not have write/execute permissions to filesystem or executables that the
user already does not have permission to outside of the container.





