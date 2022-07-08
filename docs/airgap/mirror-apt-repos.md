# Mirror Apt Repos

Set up offline repositoriy mirrors for Aptitude

## Table of Contents

- [Mirror Apt Repos](#mirror-apt-repos)
  - [Table of Contents](#table-of-contents)
  - [Summary](#summary)
  - [Identifying package repositories to mirror](#identifying-package-repositories-to-mirror)
    - [Ubuntu repositories](#ubuntu-repositories)
    - [Docker repository](#docker-repository)
      - [APT Configuration](#apt-configuration)
      - [GPG Key Validation](#gpg-key-validation)
    - [NVIDIA CUDA repository](#nvidia-cuda-repository)
      - [APT Configuration](#apt-configuration-1)
      - [GPG Key Validation](#gpg-key-validation-1)
    - [nvidia-docker](#nvidia-docker)
      - [APT Configuration](#apt-configuration-2)
      - [GPG Key Validation](#gpg-key-validation-2)
    - [Additional DEB packages](#additional-deb-packages)
  - [Downloading package repositories on a machine with Internet access](#downloading-package-repositories-on-a-machine-with-internet-access)
  - [Transferring repositories to offline network](#transferring-repositories-to-offline-network)
  - [Create mirrors on offline network](#create-mirrors-on-offline-network)

## Introduction

Most of the software necessary to run GPU-enabled applications on Ubuntu servers is available via APT repositories.
In order to deploy this software in an offline environment, the most straightforward path is to mirror the repositories in your offline network.

## Identifying package repositories to mirror

In order to mirror package repositories to use offline, you must first identify which repositories contain the software you need.
For APT repositories, this means identifying the appropriate lines in the `/etc/apt/sources.list` or `/etc/apt/sources.list.d/` configuration.

If you have a test system in an environment with Internet access, you can check which APT sources are in use with the following process:

```bash
cd /etc/apt
grep http sources.list
grep -R http sources.list.d/
```

The rest of this section lists the configuration for common repositories used by DeepOps.

### Ubuntu repositories

DeepOps assumes that a full mirror of your Ubuntu distribution repositories will be available for package installs.
If you do not already have these distribution repositories available, the `sources.list` configuration should be:

```bash
deb http://security.ubuntu.com/ubuntu <release-name>-security main
deb http://security.ubuntu.com/ubuntu <release-name>-security universe
deb http://security.ubuntu.com/ubuntu <release-name>-security multiverse
deb http://archive.ubuntu.com/ubuntu/ <release-name> main multiverse universe
deb http://archive.ubuntu.com/ubuntu/ <release-name>-updates main multiverse universe
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.

### Docker repository

#### APT Configuration

```bash
deb https://download.docker.com/linux/ubuntu <release-name> stable
```

#### GPG Key Validation

```bash
https://download.docker.com/linux/ubuntu/gpg
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.

### NVIDIA CUDA repository

#### APT Configuration

**Ubuntu 18.04**

```bash
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804
```

**Ubuntu 20.04**

```bash
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004
```

#### GPG Key Validation

**Ubuntu 18.04**

```bash
https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
```

**Ubuntu 20.04**

```bash
https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub
```

### nvidia-docker

#### APT Configuration

**Ubuntu 18.04**

```bash
deb https://nvidia.github.io/libnvidia-container/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/$(ARCH)
```

**Ubuntu 20.04**

```bash
deb https://nvidia.github.io/libnvidia-container/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/$(ARCH)
```

#### GPG Key Validation

```bash
https://nvidia.github.io/nvidia-docker/gpgkey
```

### Additional DEB packages

The following DEB files are not installed from an APT repository, but installed ad-hoc from direct URLs or file paths.

- _NVIDIA DCGM_: Requires registration, download from [DCGM site](https://developer.nvidia.com/dcgm)
- _NVIDIA Enroot_: Download from [Enroot releases](https://github.com/NVIDIA/enroot/releases/)
- _TurboVNC_: Download from [TurboVNC](https://downloads.sourceforge.net/project/turbovnc/2.2.4/turbovnc_2.2.4_amd64.deb)

## Downloading package repositories on a machine with Internet access

On an Ubuntu machine with Internet access, install the `apt-mirror` package:

```bash
sudo apt update
sudo apt install apt-mirror
```

After installing `apt-mirror`, edit the `/etc/apt/mirror.list` file make the following changes:

- Set the `base_path` to the desired download path for your mirror (here, `/var/repos`)
- Add a list of APT configuration lines for each repo you wish to mirror

For example, if we just want to mirror the Docker and NVIDIA Docker repositories, this configuration would work:

```
############# config ##################
#
set base_path    /var/repos
set nthreads     20
set _tilde 0
#
############# end config ##############

deb https://download.docker.com/linux/ubuntu bionic stable
deb https://nvidia.github.io/nvidia-docker/ubuntu20.04/amd64 /
```

Then create the target directory and run `apt-mirror`:

```bash
sudo mkdir /var/repos
sudo apt-mirror
```

## Transferring repositories to offline network

After downloading the repository contents, you will need to transfer the downloaded files to your offline network.

There are many ways to do this, depending on your local setup!
You should use the mechanism that gives you the best performance and ease-of-use in your environment.

One common way to accomplish this transfer is to bundle the downloaded files into an ISO file, which can then be moved to the offline environment or to a DVD or external USB drive.

```bash
sudo yum install genisoimage
sudo genisoimage -o /tmp/packages.iso /var/repos
```

## Create mirrors on offline network

One the repository contents have been transferred to the offline network, they need to be made available as repositories for package installs.
Your offline enviroment may already have a package server, and there are many free and commercial solutions to do this!

If you don't already have a package server, the following process shows a minimal approach using an Apache httpd server.

First, in the offline network, pick a machine to use as your package server.
We will assume the use of the Apache httpd server and that the web root is `/var/www/html`:

```bash
sudo apt update
sudo apt install apache2
sudo mkdir /var/www/html/repos
```

Then, from the extracted mirror directory,
copy the directories for each repository into the web root.
For example, assuming the extracted mirror directory is `/var/repos` and the repository is `nvidia-docker`:

```bash
sudo cp -r /var/repos/mirror/nvidia.github.com/nvidia-docker/ /var/www/html/repos/nvidia-docker/
```

At this point, the downloaded package repositories should be available on your offline network via the package server.
You can then add these downloaded repos to the `/etc/apt/sources.list` configuration on the servers that need to install the packages, e.g.:

```
# Line added to /etc/apt/sources.list
deb http://repo-server/repos/nvidia-docker/ubuntu20.04/amd64 /
```
