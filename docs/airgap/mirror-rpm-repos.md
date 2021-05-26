Setting up offline mirrors for RPM repositories
===============================================


Summary
-------

Most of the software necessary to run GPU-enabled applications on RHEL or CentOS servers is available via RPM repositories.
In order to deploy this software in an offline environment, the most straightforward path is to mirror the repositories in your offline network.


Identifying package repositories to mirror
------------------------------------------

In order to mirror package repositories to use offline, you must first identify which repositories contain the software you need.

DeepOps assumes that a full mirror of your Linux distribution repositories will be available for package installs.
If you do not already have mirrors of the distribution repositories available, please follow the
[instructions provided by Red Hat for creating these mirrors](https://access.redhat.com/solutions/23016).

The following additional RPM repositories are commonly used for GPU-enabled systems deployed by DeepOps:

- [Fedora Extra Packages for Enterprise Linux (EPEL)](https://fedoraproject.org/wiki/EPEL)
- NVIDIA CUDA repository: [repo file for EL7](https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo), [repo file for EL8](https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel8.repo)
- NVIDIA container repositories: [repo file for EL7](https://raw.githubusercontent.com/NVIDIA/nvidia-docker/gh-pages/centos7/nvidia-docker.repo), [repo file for EL8](https://raw.githubusercontent.com/NVIDIA/nvidia-docker/gh-pages/centos8/nvidia-docker.repo)
- Docker CE repository: [repo file](https://download.docker.com/linux/centos/docker-ce.repo)

These repo files provide the following repository IDs, which will be needed by `reposync` below:

- epel
- cuda-rhel7-x86\_64 or cuda-rhel8-x86\_64
- libnvidia-container
- nvidia-container-runtime
- nvidia-docker
- docker-ce-stable

To discover a complete list of repositories needed for your particular workload,
we recommend configuring a server with Internet access with the necessary software and validating your list against the contents of `/etc/yum.repos.d`.


Downloading package repositories on a machine with Internet access
------------------------------------------------------------------

On a RHEL or CentOS machine with Internet access, install the `yum-utils` and `createrepo` packages:

```
$ sudo yum install yum-utils createrepo
```

Then install the EPEL repository:

```
$ sudo yum install  https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```

Then, for each of the other repo files, install the file into the `/etc/yum.repos.d` directory.
For example, if using the list of repositories from the previous section:

```
$ cd /etc/yum.repos.d
$ sudo wget https://download.docker.com/linux/centos/docker-ce.repo
$ sudo wget https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo
$ sudo wget https://raw.githubusercontent.com/NVIDIA/nvidia-docker/gh-pages/centos7/nvidia-docker.repo
```

For each of the repositories you wish to mirror, run the `reposync` command to download the contents of the repository.
This command will use the repository ID from the repo file to identify the repository to be downloaded.

In this example, we're downloading our packages to the local path `/var/repos`, but you may substitute a different path where you want to download packages:

```
$ sudo reposync -l --repoid=docker-ce-stable --downloadcomps --download-metadata --download_path=/var/repos
```

Repeat this for each repository ID you wish to mirror.

At this point, you should have one subdirectory for each of the repositories you chose to mirror, e.g.:

```
$ ls /var/repos/
docker-ce-stable  nvidia-docker
```

For each of these directories, run the `createrepo` command to generate repository metadata:

```
$ sudo createrepo /var/repos/docker-ce-stable
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
$ sudo yum install httpd
$ sudo systemctl start httpd
$ sudo mkdir /var/www/html/repos
```

Then extract and copy your downloaded package files to `/var/www/html/repos`.

At this point, the downloaded package repositories should be available on your offline network via the package server.
You can then create repo files on the offline network to allow other hosts to use the package repositories.
For example, a new repo file for the docker-ce-stable repository might look like this:

```
[docker-ce-stable]
name=Docker CE
baseurl=http://<my-package-server>/repos/docker-ce-stable
enabled=1
```

You can then add these repo files to `/etc/yum.repos.d` on any machine where you want to install these packages.
