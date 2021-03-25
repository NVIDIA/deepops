#!/bin/bash -ex
set -ex
source workloads/jenkins/scripts/jenkins-common.sh

cd virtual || exit 1
bash ./vagrant_shutdown.sh || true # Some previous VMs may not have been cleaned; this may fail if the environment is clean; so we proceed regardless
bash ./vagrant_startup.sh # If this fails the entire test should halt
cat virtual_inventory* # We can't look at config/inventory because that is created after this step
cat Vagrantfile
