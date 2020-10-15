#!/bin/bash
set -xe

source config/pxe/env

compose_directory_cmd="" #"--project-directory ."
compose_cmd="docker-compose --env-file ./config/pxe/env ${compose_directory} -f ${COMPOSE_FILE}"


function tear_down() {
    ${compose_cmd} down
}

function build() {
    ${compose_cmd} build
}

function bring_up() {
    ${compose_cmd} up -d
}


tear_down
build
bring_up
