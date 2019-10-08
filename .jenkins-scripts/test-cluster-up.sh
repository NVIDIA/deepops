#!/bin/bash
pwd
cd virtual || exit 1
bash ./vagrant_startup.sh
bash ./cluster_up.sh
