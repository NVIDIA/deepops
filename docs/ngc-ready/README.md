# NGC Ready Server Deployment Guide

NVIDIA® GPU Cloud (NGC) containers leverage the power of NGC-Ready servers with NVIDIA GPUs. This document describes how to set up your NGC-Ready server with a software stack optimized to run NGC containers.

- [NGC Ready Server Deployment Guide](#ngc-ready-server-deployment-guide)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
  - [Installation](#installation)
  - [Testing](#testing)

## Prerequisites

These instructions assume the following:

- You have a NGC-Ready server. To determine if your server is NGC-Ready, please review the list of validated servers at the NGC-Ready Server documentation page - https://docs.nvidia.com/certification-programs/ngc-ready-systems/index.html
- Your NGC-Ready Server has a compatible Linux distribution installed:
  - Ubuntu Server 22.04 LTS
  - Ubuntu Server 24.04 LTS
  - Red Hat Enterprise Linux / Rocky Linux 8 or 9 when the referenced roles are validated for your server

Legacy Ubuntu 20.04 and CentOS 7 environments may still work for existing deployments, but they are not current release validation targets.

## Setup

NGC-Ready Server setup can be done from the NGC-Ready server itself or a 'control' machine such as a laptop with SSH access to the NGC-Ready Server.

```bash
# Clone code repo and install pre-requisite software
git clone https://github.com/NVIDIA/deepops.git
cd deepops
./scripts/setup.sh
```

## Installation

This process will install the latest NVIDIA GPU Drivers, and Docker with the NVIDIA container runtime.

```bash
# Install NGC-Ready software stack
# where:
#   <ssh-user>: SSH username to reach NGC-Ready server
#   <ip-of-host>: IP of NGC-Ready server, or localhost. The trailing comma is required
# If SSH requires a password, add: -k
# If sudo requires a password, add: -K
ansible-playbook -u <ssh-user> -i <ip-of-host>, playbooks/ngc-ready-server.yml
```

## Testing

This process will test the functionality of the NGC-Ready server by running a functional test and two deep learning framework container tests from the NVIDIA Container Registry.

```bash
# Run NGC-Ready tests
# where:
#   <ssh-user>: SSH username to reach NGC-Ready server
#   <ip-of-host>: IP of NGC-Ready server, or localhost. The trailing comma is required
# If SSH requires a password, add: -k
# If sudo requires a password, add: -K
ansible-playbook -u <ssh-user> -i <ip-of-host>, playbooks/ngc-ready-server.yml --tags test
```
