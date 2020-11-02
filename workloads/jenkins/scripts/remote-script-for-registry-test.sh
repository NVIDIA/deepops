#!/usr/bin/env bash

set -ex

# Pull nginx container locally
sudo docker pull nginx:latest

# Tag docker container for local cluster registry
sudo docker tag nginx registry.local:31500/nginx

# Push to the local registry
sudo docker push registry.local:31500/nginx 
