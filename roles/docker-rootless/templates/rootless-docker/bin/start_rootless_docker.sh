#!/bin/bash

quiet=false

usage() {
cat <<EOF
Usage: $(basename $0) [-h|--help] [--quiet]
    Start rootless docker daemon.
    Example:
        $(basename $0)

    To ommit rootless docker daemon messages redirect output to dev null or
    specify quiet option:
        $(basename $0) > /dev/null 2>&1

    --quiet - Ommit rootless docker messages. Do not use this option when
        troubleshooting.
        Default: ${quiet}

    -h|--help - Displays this help.

EOF
}


while getopts ":h-" arg; do
    case "${arg}" in
    h ) usage; exit 2 ;;
    - ) [ $OPTIND -ge 1 ] && optind=$(expr $OPTIND - 1 ) || optind=$OPTIND
        eval _OPTION="\$$optind"
        OPTARG=$(echo $_OPTION | cut -d'=' -f2)
        OPTION=$(echo $_OPTION | cut -d'=' -f1)
        case $OPTION in
        --quiet ) larguments=no; quiet=true  ;;
        --help ) usage; exit 2 ;;
        esac
        OPTIND=1
        shift
        ;;
    esac
done


function start_docker_rootless() {
    # Expects environment vars XDG_RUNTIME_DIR, DOCKER_HOST, and
    # DOCKER_DATAROOT to be set. Also, rootless docker i.e. docker-rootless.sh
    # needs to be on the PATH.

    userid=$(id -u)

    # Using dockerd
    # export XDG_RUNTIME_DIR=/var/tmp/xdg_runtime_dir_${userid}
    mkdir -p ${XDG_RUNTIME_DIR}
    # export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/docker.sock

    dockerd-rootless.sh --experimental \
      --data-root=${DOCKER_DATAROOT} \
{% if ansible_distribution == "Ubuntu" %}
      --storage-driver overlay2 &
{% elif ansible_os_family == "RedHat" and ansible_distribution_major_version == "8" %}
      --storage-driver fuse-overlayfs &
{% else %}
      --storage-driver vfs &
{% endif %}

    # Insure that docker daemon started.
    docker ps >/dev/null
    while [ $? -ne 0 ]; do
        docker ps >/dev/null
    done

}

if [ "$quiet" = true ] ; then
    start_docker_rootless >/dev/null 2>&1
else
    start_docker_rootless
fi
