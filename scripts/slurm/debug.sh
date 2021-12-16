#!/usr/bin/env bash
# This is a basic debug script for Slurm clusters
# Please use this script to collect a log bundle when opening a support request or asking for debug assistance

# Ideally this is run out of the DeepOps repo used to deploy the cluster
# However, this script will also work best-effort for any Slurm cluster, DeepOps or otherwise
# Requirements for this script are a working Slurm CLI
# Optionally, a working "ansible" with a config/inventory file that has slurm node defined in a slurm-node group

timestamp=$(date +%s)
logdir=config/log_${timestamp}
mkdir -p ${logdir}

# Provisioner configuration (specific to DeepOps deployments)
cp config/inventory ${logdir}
git branch > ${logdir}/git-branch.log
git status > ${logdir}/git-status.log
git diff > ${logdir}/git-diff.log
git log --pretty=oneline | head -n 20 > ${logdir}/git-log.log

# GPU configuration
ansible slurm-node -ba "nvidia-smi" -vv > ${logdir}/nvidia-smi.log
ansible slurm-node -ba "cat /etc/nvidia/gridd.conf" -vv > ${logdir}/vgpu-gridd.conf.log

# Docker configuration
ansible slurm-node -ba "docker info" -vv > ${logdir}/docker-info.log
ansible slurm-node -ba "docker ps -a" -vv > ${logdir}/docker-ps.log
ansible slurm-node -ba "cat /etc/docker/daemon.json" -vv > ${logdir}/docker-daemon.log

# Login node debug
ansible slurm-master -ba "srun --mpi=list" -vv > ${logdir}/srun.log
ansible slurm-master -ba "scontrol ping" -vv > ${logdir}/scontrol.log
ansible slurm-master -ba "sinfo" -vv > ${logdir}/sinfo.log
ansible slurm-master -ba "squeue" -vv > ${logdir}/squeue.log

# DCGM example output / metrics
# Collect metrics from all nodes for debug
ansible slurm-node -vv -bm raw -a "curl http://127.0.0.1:9400/metrics" > ${logdir}/dcgm-metrics.log

# Packaging
name="config/slurm-debug-${timestamp}.tgz"
tar -zcf ${name} ${logdir}
echo "A Slurm/Docker log bundle has been created at ${name}"
