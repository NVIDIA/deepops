# Docker registry logins

Many of the workloads enabled by DeepOps rely on container images distributed through registries such as [Docker Hub](https://hub.docker.com) or [NVIDIA NGC](https://ngc.nvidia.com).
While many of these container images can be downloaded without logging in, logging in may be required to access some images.
On Docker Hub, logging in also enables [higher rate limits](https://www.docker.com/increase-rate-limits) for container pulls.

## Kubernetes pods using private registries

To use container images from private registries for Kubernetes pods, you will need to create a Kubernetes Secret which contains the relevant credentials.
The easiest method is to provide the credentials directly on the command line:

```
kubectl create secret docker-registry regcred --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```

Then, when creating a pod, you will need to specify this secret in the `imagePullSecrets` section of your container spec:

```
apiVersion: v1
kind: Pod
metadata:
  name: private-reg
spec:
  containers:
  - name: private-reg-container
    image: <your-private-image>
  imagePullSecrets:
  - name: regcred
```

The [Kubernetes documentation](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/) has more detail on setting this up.


## Slurm jobs using private registries

The process for using private registries is different depending on whether you are using Singularity or Enroot as your container runtime.

### Singularity

[Singularity](https://sylabs.io/singularity/) gets container pull credentials using environment variables:

```
$ export SINGULARITY_DOCKER_USERNAME=<username>
$ export SINGULARITY_DOCKER_PASSWORD=<password>
``` 

Note that because Singularity downloads the container image to a file in your local directory, you can typically pull the container before running your Slurm job, and then make use of the downloaded file in your job. 

The [Singularity documentation](https://sylabs.io/guides/3.5/user-guide/singularity_and_docker.html#making-use-of-private-images-from-docker-hub) has more detail on how to use private images.

### Enroot

[Enroot](https://github.com/NVIDIA/enroot) uses credentials configured through `$ENROOT_CONFIG_PATH/.credentials`.
In most Slurm installations, `ENROOT_CONFIG_PATH` will be `$HOME/.config`.
Because Enroot pulls containers on the fly as Slurm jobs start, the credentials file needs to be accessible in a shared filesystem which all nodes can access at job start.

The file format for the credentials file looks like this:

```
machine <hostname> login <username> password <password>
```

So, for example:

```
machine auth.docker.io login <username> password <password>
```

For more information, see the [Enroot documentation](https://github.com/NVIDIA/enroot/blob/master/doc/cmd/import.md#description).
 
## System containers using private registries

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
