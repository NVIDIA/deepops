Building DeepOps Offline
========================

## UNDER CONSTRUCTION

This feature is currently incomplete and in development.
Currently only CentOS is targeted for offline support.

## Dependencies for an offline build

DeepOps depends on a wide variety of software dependencies, which are normally downloaded from the Internet as-needed.
In order to build DeepOps without Internet access, we need to download all these dependencies in advance and make them available in such a way that the build can proceed.

We do this in two steps:

1. Download all dependencies on an Internet-connected host and build a `tar` archive for transfer.
1. Extract the archive on a disconnected host, and use the contents to set up software repositories for DeepOps to use.

### Downloading dependencies

To download all dependencies for an offline build, you need a CentOS or Ubuntu host with Ansible and Docker installed.
You will need at least 100 GB of free disk space to build the archive, and the final `tar` file will be at least 50 GB.

To start an offline build, run the following script:

```
./scripts/build_offline_cache.sh
```

Currently this script will download:

* Docker container images used in a default build of DeepOps
* Dependencies needed by Kubespray
* Python packages installed by the DeepOps playbooks
* All Helm charts from the repos used by DeepOps
* All RPM packages in the NVIDIA `cuda`, `nvidia-docker`, `nvidia-container-runtime`, and `libnvidia-container` Yum repositories
    * The download playbook is also capable of mirroring the CentOS, EPEL, and Docker repositories, but we disable this by default on the assumption that most sites will already have these mirrors.
        To enable download of these packages, see the configuration for the `offline-repo-mirrors` role.

Downloaded dependencies will be archived in `/tmp/deepops-archive.tar` by default.

To configure the download, see the variables in `scripts/build_offline_cache.sh` and in `roles/offline-repo-mirrors/defaults/main.yml`.

### Building the offline mirrors

To set up the mirrors for your offline build, you will also need a CentOS or Ubuntu host with Ansible and Docker installed in your offline network.
This host should have at least 200 GB of free disk space, so you can extract the archive and set up the mirrors.

Copy `deepops-archive.tar` to your destination host, then run:

```
ansible-playbook -e tar_file_path="<path_to_archive>" playbooks/build-offline-mirrors.yml
```

This playbook will extract the `tar` file, copy its contents to `/opt/deepops` on the local host, and set up several software repositories using Docker.
These will include:

* A Docker registry container serving the Docker images at port 5000
* An NGINX container serving the Yum repositories at port 8001
* A Chart Museum container for the Helm charts at port 8002
* A PyPI server container for the Python packages at port 8003
* An NGINX container serving miscellaneous download files over HTTP at port 8004

You don't need to have any of the images for these containers downloaded in advance.
The necessary images will be imported as part of the setup process.
To configure this process and enable or disable some services, see `roles/offline-repo-mirrors/defaults/main.yml`.

## Performing an offline build

TBD
