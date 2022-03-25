#!/usr/bin/env bash

set -ex

# Pull nginx container locally
sudo ctr images pull --all-platforms docker.io/library/nginx:1.21

# Tag docker container for local cluster registry
sudo ctr images tag docker.io/library/nginx:1.21 registry.local:31500/nginx:1.21

# Push to the local registry
sudo ctr images push --plain-http registry.local:31500/nginx:1.21
