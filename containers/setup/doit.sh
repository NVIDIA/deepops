#!/usr/bin/env bash

export ENROOT_RUNTIME_PATH=${ENROOT_RUNTIME_PATH:-/tmp/enroot/runtime}
export ENROOT_CACHE_PATH=${ENROOT_CACHE_PATH:-/tmp/enroot/cache}
export ENROOT_DATA_PATH=${ENROOT_DATA_PATH:-/tmp/enroot/data}
export ENROOT_TEMP_PATH=${ENROOT_TEMP_PATH:-/tmp/enroot/tmp}

rm -rf ${ENROOT_RUNTIME_PATH} ${ENROOT_CACHE_PATH} ${ENROOT_DATA_PATH} ${ENROOT_TEMP_PATH}
mkdir -p ${ENROOT_RUNTIME_PATH} ${ENROOT_CACHE_PATH} ${ENROOT_DATA_PATH} ${ENROOT_TEMP_PATH}

rm -f ubuntu.sqsh deepops.sqsh deepops.run

# import docker image
enroot import docker://ubuntu

# create enroot image
enroot create ubuntu.sqsh

# start and build container
enroot batch ./build

# export container as image
enroot export -o deepops.sqsh ubuntu

# bundle image as standalone binary
enroot bundle deepops.sqsh
