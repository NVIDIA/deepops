Ubuntu package repositories
===========================

## Overview

In most cases, it will be easier to build full mirrors of OS package repositories, than to try to identify individual packages to mirror.

- Most clusters will have a very large number of packages installed, making it cumbersome to come up with a full list
- Many operational tasks on the cluster may require installing new packages
- Good tools already exist for building full mirrors of OS package repositories

This document will therefore focus on outlining how to build full mirrors, rather than enumerating individual packages to install for a given DeepOps configuration.

## Identifying package repositories to mirror

In order to identify APT repositories you may wish to mirror, we recommend building a test system in an environment with Internet access, then identifying the repositories used.
This can be done relatively easily by checking which repositories are configured in the `/etc/apt` directory of each host:

```
$ cd /etc/apt
$ grep http sources.list
$ grep -R http sources.list.d/
```

This should provide a list of APT configuration lines for the repositories you used to build the test environment.

### Known repositories you may want to mirror

#### Ubuntu OS repositories

```
deb http://security.ubuntu.com/ubuntu <release-name>-security main
deb http://security.ubuntu.com/ubuntu <release-name>-security universe
deb http://security.ubuntu.com/ubuntu <release-name>-security multiverse
deb http://archive.ubuntu.com/ubuntu/ <release-name> main multiverse universe
deb http://archive.ubuntu.com/ubuntu/ <release-name>-updates main multiverse universe
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.


#### NVIDIA CUDA repository

```
# For Ubuntu 18.04
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804 /

# For Ubuntu 20.04
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004 /
``` 


#### Docker repository

```
deb https://download.docker.com/linux/ubuntu <release-name> stable
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.

#### nvidia-docker

```
# For Ubuntu 18.04
deb https://nvidia.github.io/nvidia-container-runtime/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/$(ARCH) /

# For Ubuntu 20.04
deb https://nvidia.github.io/nvidia-container-runtime/ubuntu20.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu20.04/$(ARCH) /
```

### Additional DEB packages

The following DEB files are not installed from an APT repository, but installed ad-hoc from direct URLs or file paths.

- *NVIDIA DCGM*: Requires registration, download from [DCGM site](https://developer.nvidia.com/dcgm)
- *NVIDIA Enroot*: Download from [Enroot releases](https://github.com/NVIDIA/enroot/releases/)
- *TurboVNC*: Download from [TurboVNC](https://downloads.sourceforge.net/project/turbovnc/2.2.4/turbovnc_2.2.4_amd64.deb)


## Building APT mirrors for offline use

### Downloading packages

Ubuntu provides the `debmirror` tool which can be used to download the full contents of remote repositories.

- [How to use debmirror](https://help.ubuntu.com/community/Debmirror)
- [manual page](http://manpages.org/debmirror)

Note that the resulting download may be quite large!
Ensure you have enough space on your download host to store all the files you plan to download.

### Transferring files to offline host

After downloading the contents of the remote repositories, you should may need to move the downloaded files to the host you plan to use for the mirror.
For example, if you are building a new cluster in an environment with no Internet access at all, you will likely need to place the downloaded files on an external storage device and "sneakernet" it to the offline environment.

These are many ways to do this, but one simple method is to create an ISO file.
A good tool to use for this is `genisoimage`:

```
$ genisoimage -o output_image.iso /path/to/apt/mirror
```

You can then transfer this file to your storage of device of choice for transfer.

### Configuring the mirror server

In order to serve the mirrored files to the cluster, you will need to set up an HTTP server ...
