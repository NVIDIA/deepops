# Docker registry logins

Many of the workloads enabled by DeepOps rely on container images distributed through registries such as [Docker Hub](https://hub.docker.com) or [NVIDIA NGC](https://ngc.nvidia.com).
While many of these container images can be downloaded without logging in, logging in may be required to access some images.
On Docker Hub, logging in also enables [higher rate limits](https://www.docker.com/increase-rate-limits) for container pulls.

DeepOps performs some container pulls as part of setting up a cluster, so many deployments will want to enable a registry login for the root user during the setup process.
To enable this, we provide a convenience playbook [docker-login.yml](../playbooks/container/docker-login.yml) that you can use to log into one or more registries on each node in a cluster.
Note that we recommend registering a separate service account on the container registries for system setup, rather than relying on the individual account of an individual person.

First, create an Ansible vars file to store your registry login information.
You can put this directly in your DeepOps [config directory](../config.example), but for security, we recommend creating a separate [Ansible Vault](https://docs.ansible.com/ansible/2.8/user_guide/vault.html) file.

```
$ ansible-vault create config/docker-login.yml
New Vault password:
Confirm New Vault password:
```

This will open your editor of choice, where you can enter the login information in a `docker_login_registries` variable.
An example appears below, or in the [defaults for the docker-login role](../roles/docker-login/defaults/main.yml):

```
docker_login_registries:
- registry: nvcr.io
  username: '$oauthtoken'
  password: '<api-token>'
- registry: docker.io
  username: 'my-docker-username'
  password: 'my-docker-password'
```

Once you have created the Vault file, you can run the `docker-login.yml` playbook, entering the password during the playbook run:

```
$ ansible-playbook -e @config/docker-login.yml --ask-vault-pass playbooks/container/docker-login.yml
Vault password:

PLAY [all] **************************************************

...
```

Once the playbook runs, subsequent docker pulls from the registries you specify will use the credentials you used to log in.
This will enable the root user to pull containers which may require logging in, e.g.

```
# docker pull nvcr.io/nvidia/hpc-benchmarks:20.10-hpl
20.10-hpl: Pulling from nvidia/hpc-benchmarks
f52357ed8777: Pull complete
...
```

Note that only the root user will use these credentials.
Other users of the cluster should provide their own docker logins to use private containers.
