Setting up offline mirrors for APT repositories
===============================================

Summary
-------

Most of the software necessary to run GPU-enabled applications on Ubuntu servers is available via APT repositories.
In order to deploy this software in an offline environment, the most straightforward path is to mirror the repositories in your offline network.


Identifying package repositories to mirror
------------------------------------------

In order to mirror package repositories to use offline, you must first identify which repositories contain the software you need.
For APT repositories, this means identifying the appropriate lines in the `/etc/apt/sources.list` or `/etc/apt/sources.list.d/` configuration.

If you have a test system in an environment with Internet access, you can check which APT sources are in use with the following process:

```
$ cd /etc/apt
$ grep http sources.list
$ grep -R http sources.list.d/
```

The rest of this section lists the configuration for common repositories used by DeepOps.

### Ubuntu repositories

DeepOps assumes that a full mirror of your Ubuntu distribution repositories will be available for package installs.
If you do not already have these distribution repositories available, the `sources.list` configuration should be:

```
deb http://security.ubuntu.com/ubuntu <release-name>-security main
deb http://security.ubuntu.com/ubuntu <release-name>-security universe
deb http://security.ubuntu.com/ubuntu <release-name>-security multiverse
deb http://archive.ubuntu.com/ubuntu/ <release-name> main multiverse universe
deb http://archive.ubuntu.com/ubuntu/ <release-name>-updates main multiverse universe
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.


### Docker repository

APT configuration: 

```
deb https://download.docker.com/linux/ubuntu <release-name> stable
```

GPG key for validation:

```
https://download.docker.com/linux/ubuntu/gpg
```

where `<release-name>` is the name of the Ubuntu release you want to mirror.
This is `bionic` for Ubuntu 18.04, and `focal` for Ubuntu 20.04.


### NVIDIA CUDA repository

APT configuration:

```
# For Ubuntu 18.04
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804 /
# For Ubuntu 20.04
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004 /
``` 

GPG key for validation:

```
# For Ubuntu 18.04
https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
# For Ubuntu 20.04
https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub
```

### nvidia-docker

APT configuration:

```
# For Ubuntu 18.04
deb https://nvidia.github.io/libnvidia-container/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/$(ARCH) /
# For Ubuntu 20.04
deb https://nvidia.github.io/libnvidia-container/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/stable/ubuntu18.04/$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/$(ARCH) /
```

GPG key for validation:

```
https://nvidia.github.io/nvidia-docker/gpgkey
```

### Additional DEB packages

The following DEB files are not installed from an APT repository, but installed ad-hoc from direct URLs or file paths.

- *NVIDIA DCGM*: Requires registration, download from [DCGM site](https://developer.nvidia.com/dcgm)
- *NVIDIA Enroot*: Download from [Enroot releases](https://github.com/NVIDIA/enroot/releases/)
- *TurboVNC*: Download from [TurboVNC](https://downloads.sourceforge.net/project/turbovnc/2.2.4/turbovnc_2.2.4_amd64.deb)


Downloading package repositories on a machine with Internet access
------------------------------------------------------------------

On an Ubuntu machine with Internet access, install the `apt-mirror` package:

```
sudo apt update
sudo apt install apt-mirror
```

After installing `apt-mirror`, edit the `/etc/apt/mirror.list` file make the following changes:

* Set the `base_path` to the desired download path for your mirror (here, `/var/repos`)
* Add a list of APT configuration lines for each repo you wish to mirror

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

```
$ sudo mkdir /var/repos
$ sudo apt-mirror
```


Transferring repositories to offline network
--------------------------------------------

After downloading the repository contents, you will need to transfer the downloaded files to your offline network.

There are many ways to do this, depending on your local setup!
You should use the mechanism that gives you the best performance and ease-of-use in your environment.

One common way to accomplish this transfer is to bundle the downloaded files into an ISO file, which can then be moved to the offline environment or "burned" to a DVD or external USB drive.

```
$ sudo yum install genisoimage
$ sudo genisoimage -o /tmp/packages.iso /var/repos
```


Create mirrors on offline network
---------------------------------

One the repository contents have been transferred to the offline network, they need to be made available as repositories for package installs.
Your offline enviroment may already have a package server, and there are many free and commercial solutions to do this!

If you don't already have a package server, the following process shows a minimal approach using an Apache httpd server.

First, in the offline network, pick a machine to use as your package server.
We will assume the use of the Apache httpd server and that the web root is `/var/www/html`:

```
$ sudo apt update
$ sudo apt install apache2
$ sudo mkdir /var/www/html/repos
```

Then, from the extracted mirror directory,
copy the directories for each repository into the web root.
For example, assuming the extracted mirror directory is `/var/repos` and the repository is `nvidia-docker`:

```
$ sudo cp -r /var/repos/mirror/nvidia.github.com/nvidia-docker/ /var/www/html/repos/nvidia-docker/
```

At this point, the downloaded package repositories should be available on your offline network via the package server.
You can then add these downloaded repos to the `/etc/apt/sources.list` configuration on the servers that need to install the packages, e.g.:

```
# Line added to /etc/apt/sources.list
deb http://repo-server/repos/nvidia-docker/ubuntu20.04/amd64 /
```
