#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh


# Ensure working directory is virtual, so downstream Ansible picks up the correct inventory
cd "${VIRT_DIR}/virtual"

#  Collect all the standard debug
${ROOT_DIR}/scripts/slurm/debug.sh

# The debug script will create a time-stamped log dir
logdir=$(ls -Art ./config | grep log_ | tail -n 1)

# Iterate over each .log file and pring to screen, ignoring the tar
for logfile in $(ls ./config/${logdir}/*log); do
    cat ${logfile}
done
