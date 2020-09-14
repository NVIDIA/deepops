#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1
export DEEPOPS_DISABLE_K8S=true
export DEEPOPS_ENABLE_SLURM=true
bash ./cluster_up.sh
