#!/bin/bash
source .jenkins-scripts/jenkins-common.sh

cd virtual || exit 1
bash ./cluster_up.sh
