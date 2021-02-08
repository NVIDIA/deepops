Building DeepOps Offline
========================

## EXPERIMENTAL

Deploying DeepOps without Internet access is currently an experimental feature and is still in development.
This is not guaranteed to work for any given release, and may break without notice.

In our current iteration,

- Currently only CentOS is targeted for offline support.
- DGXie and PXE containers are not yet supported.
- Limited support for optional features (e.g. deployments in the `scripts/` directory).

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
ansible-playbook -e tar_file_path="<path_to_archive>" playbooks/airgap/build-offline-mirrors.yml
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

## Building a DeepOps cluster offline

The primary difference between an "offline" build and an "online" one is what upstream servers it uses to download its software.
In order to build DeepOps on a network without access to the Internet, you have to ensure that the Ansible playbooks and other scripts used to set up the cluster know where to find the software they need to install.
We do this by overriding a collection of Ansible variables and environment variables used by DeepOps to control the download locations.

### Considerations for configuring DeepOps

- If building an offline Slurm cluster, please configure `hosts_network_interface` in the DeepOps configuration to specify the primary network interface on your offline hosts.
    This will ensure that the cluster `/etc/hosts` file uses the correct IP addresses for your nodes.

### Specifying mirror locations

1. Edit `config/airgap/offline_repo_vars.yml` file to specify your repository mirror locations for Ansible.
    1. If you have set up a mirror server using the instructions above, you should be able to edit just the deepops_mirror_host` variable to point to the correct host.
    1. If you are using different locations or port numbers for some or all of the mirrors, you should edit the variables for particular types of mirrors, e.g. `deepops_docker_mirror` or `deepops_charts_mirror`.
        Note that some file downloads are not part of any particular type of repository; those files will be downloaded from `deepops_misc_mirror`.
    1. If you need to specify particular locations for some downloads or container names, you can specify those individually in the rest of the file.
        For example, `etcd_image_repo` specifies where to find the Docker image for `etcd`, and can be specified individually if it is not available in the larger Docker mirror.
1. Edit the `config/airgap/offline_repo_shell_vars.sh` file to specify the locations of repos used by the deployment shell scripts.
    E.g., `DEEPOPS_MISC_MIRROR` or `DEEPOPS_DOCKER_REGISTRY`.
    As with the Ansible vars file, you can also edit the individual download location variables, such as `DOCKER_COMPOSE_URL`.

### Using the mirror locations

1. Source the `config/airgap/offline_repo_shell_vars.sh` file in your local environment.
    This should correctly override download locations in any supported shell scripts.
    ```
    $ source config/airgap/offline_repo_shell_vars.sh
    ```
1. When running `ansible-playbook`, specify the `config/airgap/offline_repo_vars.yml` file as an "extra vars" file. E.g.,
    ```
    $ ansible-playbook -e @config/airgap/offline_repo_vars.yml playbooks/k8s-cluster.yml
    ```
1. If your hosts are not already configured to use local mirrors for the CentOS Yum repositories, you will need to do so before running other playbooks. You can configure them to use the DeepOps-configured Yum mirror using the following convenience playbook:
    ```
    $ ansible-playbook -e @config/airgap/offline_repo_vars.yml playbooks/airgap/use-offline-yum-mirrors.yml
    ```
