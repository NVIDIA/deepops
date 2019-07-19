#!/usr/bin/env bash

ENROOT_BIN=/usr/local/bin/enroot

export ENROOT_RUNTIME_PATH=${ENROOT_RUNTIME_PATH:-/tmp/enroot/runtime}
export ENROOT_CACHE_PATH=${ENROOT_CACHE_PATH:-/tmp/enroot/cache}
export ENROOT_DATA_PATH=${ENROOT_DATA_PATH:-/tmp/enroot/data}
export ENROOT_TEMP_PATH=${ENROOT_TEMP_PATH:-/tmp/enroot/tmp}

# default mksquashfs options
#export ENROOT_SQUASH_OPTIONS="-comp lzo -noD"
# use compression; default "lzo" requires `lzop` on target
# does make launching the .run file a little slower
export ENROOT_SQUASH_OPTIONS="-comp gzip"

rm -rf ${ENROOT_RUNTIME_PATH} ${ENROOT_CACHE_PATH} ${ENROOT_DATA_PATH} ${ENROOT_TEMP_PATH}
mkdir -p ${ENROOT_RUNTIME_PATH} ${ENROOT_CACHE_PATH} ${ENROOT_DATA_PATH} ${ENROOT_TEMP_PATH}

rm -f ubuntu.sqsh deepops.sqsh deepops.run

# import docker image
${ENROOT_BIN} import docker://ubuntu

# create enroot image
${ENROOT_BIN} create ubuntu.sqsh

# start and build container
${ENROOT_BIN} batch ./build

# export container as image
${ENROOT_BIN} export -o deepops.sqsh ubuntu

# bundle image as standalone binary
${ENROOT_BIN} bundle --target "\$PWD/deepops.bundle" deepops.sqsh
