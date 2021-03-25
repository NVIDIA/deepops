Deploying the NGC-Ready playbook offline
========================================

## Necessary software mirrors

Deploying the NGC-Ready playbook assumes that several package repositories and individual software packages are available to install.
In order to deploy this configuration without Internet access, you will need to have the following software available in offline mirrors.


### Ubuntu

The following Apt repositories will need to be mirrored in the offline environment:

* Ubuntu distribution repositories
* Docker CE repository
* nvidia-docker repositories

For instructions on mirroring these repositories, see the [doc on Apt mirrors](./mirror-apt-repos.md).


The following files will need to be downloaded and made available in an HTTP mirror:

* nvidia-docker wrapper (found [here](https://raw.githubusercontent.com/NVIDIA/nvidia-docker/master/nvidia-docker))
* DCGM package (optional)

For instructions on setting up an HTTP mirror, see the [doc on HTTP mirrors](./mirror-http-files.md).


Container images are only needed if you want to run the tests built into the playbook:

* nvcr.io/nvidia/cuda:10.1-base-ubuntu18.04
* nvcr.io/nvidia/pytorch:18.10-py3
* nvcr.io/nvidia/tensorflow:18.10-py3

For instructions on setting up a Docker registry mirror, see the [doc on Docker mirrors](./mirror-docker-images.md).


### Enterprise Linux

The following RPM repositories will need to be mirrored in the offline environment:

* Enterprise Linux distribution repositories (RHEL or CentOS, depending on your distro)
* Docker CE repository
* nvidia-docker repositories

For instructions on mirroring these repositories, see the [doc on RPM mirrors](./mirror-rpm-repos.md).


The following files will need to be downloaded and made available in an HTTP mirror:

* EPEL package (found [here](https://fedoraproject.org/wiki/EPEL))
* nvidia-docker wrapper (found [here](https://raw.githubusercontent.com/NVIDIA/nvidia-docker/master/nvidia-docker))
* DCGM package (optional)

For instructions on setting up an HTTP mirror, see the [doc on HTTP mirrors](./mirror-http-files.md).

Container images (how to mirror) are only needed if you want to run the tests built into the playbook:

* nvcr.io/nvidia/cuda:10.1-base-ubuntu18.04
* nvcr.io/nvidia/pytorch:18.10-py3
* nvcr.io/nvidia/tensorflow:18.10-py3

For instructions on setting up a Docker registry mirror, see the [doc on Docker mirrors](./mirror-docker-images.md).


## Configuring DeepOps

To deploy the NGC-Ready playbook offline, you will need to configure your servers and DeepOps to make use of your mirrors.


### Configure servers to use your mirrors for the Linux distribution package repositories

DeepOps does not configure the location of your Linux distribution's package repositories (e.g., Ubuntu or CentOS repositories).
Instead, you will need to configure your servers to use your offline package mirrors directly.

On Ubuntu servers, you should edit the `/etc/apt/sources.list` file to replace references to the Ubuntu distribution servers with your own mirror.
For example,

```
# Replace this...
deb http://us.archive.ubuntu.com/ubuntu bionic main restricted

# With this...
deb http://<your-mirror-server>/ubuntu bionic main restricted
```

On Enterprise Linux servers, you should edit the appropriate repo files in `/etc/yum.repos.d` and replace references to the upstream distribution servers with your own mirror.
For repositories that reference a `mirrorlist`, you should replace these with `baseurl` parameters.

For example,

```
# Replace this...
[base]
name=CentOS-$releasever - Base
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra
#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

# With this...
[base]
name=CentOS-$releasever - Base
baseurl=http://<your-mirror-server>/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
```

In all cases, you should edit the URLs appropriately to ensure they can download from the paths exported from your mirrors.


### Configure DeepOps to use your mirrors for non-distribution package repositories

The NGC-Ready playbook depends on the Docker CE and nvidia-docker package repositories.
DeepOps sets up these repositories automatically during the installation.

To configure alternate URLs for these repositories, set the following variables in your DeepOps configuration:

```
# Ubuntu
docker_ubuntu_repo_base_url: "http://<your-package-mirror>/<your-path-to-docker-repo>"
docker_ubuntu_repo_gpgkey: "http://<your-package-mirror>/<your-path-to-docker-gpgkey>"

nvidia_docker_repo_base_url: "http://<your-package-mirror>/<your-path-to-nvidia-docker-base-dir>"
nvidia_docker_repo_gpg_url: "http://<your-package-mirror>/<your-path-to-nvidia-docker-gpgkey>"

# Enterprise Linux
docker_rh_repo_base_url: "http://<your-package-mirror>/<your-path-to-docker-repo>"
docker_rh_repo_gpgkey: "http://<your-package-mirror>/<your-path-to-docker-gpgkey>"

nvidia_docker_repo_base_url: "http://<your-package-mirror>/<your-path-to-nvidia-docker-base-dir>"
nvidia_docker_repo_gpg_url: "http://<your-package-mirror>/<your-path-to-nvidia-docker-gpgkey>"
```


### Configure DeepOps to use your mirrors for HTTP downloads

In all cases, you will need to provide a URL to download the nvidia-docker wrapper:

```
nvidia_docker_wrapper_url: "http://<your-http-mirror>/<your-path>/nvidia-docker"
```

If installing on Enterprise Linux, you will need to provide a URL for the EPEL package.
For example,

```
epel_package: "http://<your-http-mirror>/<your-path>/epel-release.rpm"
```

If installing NVIDIA DCGM, you will need to provide a local file path for your downloaded DCGM package.

```
# For Ubuntu
dcgm_deb_package: "/path/to/datacenter-gpu-manager.deb"

# For Enterprise Linux
dcgm_rpm_package: "/path/to/datacenter-gpu-manager.rpm"
```


### Configure DeepOps to use your mirrors for container image pulls

If running the container tests as part of the NGC-Ready playbook, set the following variables in your DeepOps configuration:

```
ngc_ready_cuda_container: "<your-container-registry>/nvidia/cuda:10.1-base-ubuntu18.04"
ngc_ready_pytorch: "<your-container-registry>/nvidia/pytorch:18.10-py3"
ngc_ready_tensorflow: "<your-container-registry>/nvidia/tensorflow:18.10-py3"
``` 

## Running the NGC-Ready playbook

After setting these variables to point to your local mirrors, you should be able to run the NGC-Ready playbook:

```
ansible-playbook playbooks/ngc-ready-server.yml
```
