#!/bin/bash -ex
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1
bash ./vagrant_startup.sh # If this fails the entire test should halt
cat virtual_inventory* # We can't look at config/inventory because that is created after this step
cat Vagrantfile
