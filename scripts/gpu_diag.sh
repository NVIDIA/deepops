#!/usr/bin/env bash

diag_level=${1:-1}

hostname

# discover GPUs
dcgmi discovery -l

# remove old groups
for old_group in $(dcgmi group -l | grep "Group ID" | awk '{print $5}') ; do 
    dcgmi group -d ${old_group} >/dev/null 2>&1
done

# create new default group and record group number
new_group=$(dcgmi group -c default --default | awk '{print $NF}')

dcgmi diag -g ${new_group} -r ${diag_level}

exit 0
