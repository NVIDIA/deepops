#!/bin/bash
source .jenkins-scripts/jenkins-common.sh

cd virtual || exit 1
bash ./vagrant_startup.sh
cat config/inventory
cat Vagrantfile
