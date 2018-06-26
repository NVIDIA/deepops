#!/bin/bash
host_path=${DEEPOPS_HOST_ROOT_PATH:-/opt/deepops}
#docker pull deepops/ansible
docker run --rm -ti -v $host_path/ssh:/root/.ssh:ro -v $host_path/ansible:/data --net=host deepops/ansible bash
