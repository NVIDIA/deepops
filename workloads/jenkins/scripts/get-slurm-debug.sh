#!/bin/bash
set -x
source workloads/jenkins/scripts/jenkins-common.sh

# Ensure working directory is root
cd "${ROOT_DIR}"

#  collect all the standard debug
./scripts/slurm/debug.sh

# The debug script will create a time-stamped log dir
logdir=$(ls -Art ./config | grep log_ | tail -n 1)

# Iterate over each .log file and pring to screen, ignoring the tar
for logfile in $(ls ./config/${logdir}/*log); do
    cat ${logfile}
done
