#!/bin/bash
set -xe


compose_file=config/containers/dgxie/docker-compose-dgxie.yml
compose_directory="."
compose_cmd="docker-compose --project-directory ${compose_directory} -f ${compose_file}"


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
