#!/bin/bash

usage() {
cat <<EOF
Usage: $(basename $0) [-h|--help]
    Stop rootless docker daemon.
    Example:
        $(basename $0)

    To ommit messages redirect output to dev null.
        $(basename $0) > /dev/null 2>&1

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
        --help ) usage; exit 2 ;;
        esac
        OPTIND=1
        shift
        ;;
    esac
done


function stop_docker_rootless() {
    pkill -u $USER -f dockerd

    # Check that docker is not working
    #docker ps  >/dev/null 2>&1
    #while [ $? -eq 0 ]; do
    #    docker ps >/dev/null 2>&1
    #done
}

stop_docker_rootless
