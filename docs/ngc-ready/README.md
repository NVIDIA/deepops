NGC Ready Server Deployment Guide
===

NVIDIA® GPU Cloud (NGC) containers leverage the power of NGC-Ready servers with NVIDIA GPUs. This document describes how to set up your NGC-Ready server with a software stack optimized to run NGC containers.

## Prerequisites

These instructions assume the following:

  * You have a NGC-Ready server. To determine if your server is NGC-Ready, please review the list of validated servers at the NGC-Ready Server documentation page - https://docs.nvidia.com/ngc/ngc-ready-systems/index.html
  * Your NGC-Ready Server has a compatible Linux distribution installed:
    * Ubuntu Server 18.04 LTS
    * CentOS 7

## Setup

NGC-Ready Server setup can be done from the NGC-Ready server itself or a 'control' machine such as a laptop with SSH access to the NGC-Ready Server.

```sh
# Clone code repo and install pre-requisite software
git clone https://github.com/NVIDIA/deepops.git
cd deepops
./scripts/setup.sh
```

## Installation

This process will install the latest NVIDIA GPU Drivers, and Docker with the NVIDIA container runtime.

```sh
# Install NGC-Ready software stack
# where:
#   <ssh-user>: SSH username to reach NGC-Ready server
#   <ip-of-host>: IP of NGC-Ready server, or localhost. The trailing comma is required
# If SSH requires a password, add: -k
# If sudo requires a password, add: -K
ansible-playbook -u <ssh-user> -i <ip-of-host>, playbooks/ngc-ready.yml
```

## Testing

This process will test the functionality of the NGC-Ready server by running a functional test and two deep learning framework container tests from the NVIDIA Container Registry.

```sh
# Run NGC-Ready tests
# where:
#   <ssh-user>: SSH username to reach NGC-Ready server
#   <ip-of-host>: IP of NGC-Ready server, or localhost. The trailing comma is required
# If SSH requires a password, add: -k
# If sudo requires a password, add: -K
ansible-playbook -u <ssh-user> -i <ip-of-host>, playbooks/ngc-ready.yml --tags test
```
