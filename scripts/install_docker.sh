#!/usr/bin/env bash

type docker >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    get_docker=$(mktemp)
    curl -fsSL get.docker.com -o ${get_docker}
    sudo sh ${get_docker}
    sudo rm -f ${get_docker}
    sudo usermod -aG docker $(whoami)
fi

type docker-compose >/dev/null 2>&1
if [ $? -ne 0 ] ; then
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
fi
