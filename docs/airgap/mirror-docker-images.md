Setting up an offline mirror for Docker container images
========================================================

Identifying images to mirror
----------------------------

To identify which container images you need, we recommend configuring a server for your workload in an environment with Internet access.
Then determine the list of images by:

- If using Docker: run `docker images` on each host
- If using Singularity: check your history of `singularity` commands to identify which containers you used
- If using Pyxis/Enroot with Slurm: check your `slurmd` logs for a list of images downloaded by Pyxis


Downloading images with NGC Container Replicator
------------------------------------------------

If you are only using containers from the [NGC Catalog](https://ngc.nvidia.com), we recommend using the [NGC Replicator](https://github.com/NVIDIA/ngc-container-replicator) to download the images you need.
The NGC Replicator has helpful options that allow you to mirror a large number of images from NGC,
filtering by image name(s) or version(s) where needed.

For more information, see the [NGC Replicator documentation](https://github.com/NVIDIA/ngc-container-replicator/blob/master/README.md).


Downloading container images with Docker 
----------------------------------------

If you need containers from registries other than NGC, or if you use containers from a mix of registries, you can download the images using Docker.

On a machine with Internet access, install Docker manually or with DeepOps:

```
$ ansible-playbook playbooks/container/docker.yml
```

Then, for each image you want to download, you should pull the image from the remote registry and save it to a local file.
In this example, we're saving all our Docker images to `/tmp/images`:

```
$ docker pull nvidia/cuda:11.1-devel-ubuntu20.04
$ docker save nvidia/cuda:11.1-devel-ubuntu20.04 > /tmp/images/nvidia-cuda-11.1-devel-ubuntu20.04.tar
```

Additionally, you should download and save the [`registry` image](https://hub.docker.com/_/registry) so that you can deploy a local registry on the offline network.


Transferring images to offline network
--------------------------------------

After downloading the container images, you will need to transfer the downloaded files to your offline network.

There are many ways to do this, depending on your local setup!
You should use the mechanism that gives you the best performance and ease-of-use in your environment.

One common way to accomplish this transfer is to bundle the downloaded files into an ISO file, which can then be moved to the offline environment or "burned" to a DVD or external USB drive.

```
$ sudo apt install genisoimage
$ sudo genisoimage -o /tmp/images.iso /tmp/images
```


Set up a container registry on the offline network
--------------------------------------------------

One the container images have been transferred to the offline network, they need to be pushed to a container registry for use on your offline cluster.
Your offline environment may already have a container registry, and there are many free and commercial solutions for running a registry.

If you don't already have a container registry, we recommend using the official [Docker Registry](https://hub.docker.com/_/registry) image to deploy a new registry.

First, in the offline network, pick a host to use as your container registry.
We will assume this host already has Docker installed and can run containers which expose ports to the offline network.
Additionally, we assume that the `registry` image was included when you transferred container images from the Internet-connected machine.

Load the registry image into the Docker image cache of your container registry host:

```
$ docker load < /tmp/images/registry-2.7.tar
```

Then create a Docker volume to store your container images:

```
$ docker volume create registry-images
```

And run the registry container:

```
$ docker run -d \
    -p 5000:5000 \
    --restart=always \
    --name registry \
    -v registry-images:/var/lib/registry \
    registry:2.7
```


Configuring your hosts to use the offline container registry
------------------------------------------------------------

By default, Docker requires that connections to a container registry be secured with a TLS certificate.
If you are able to set up a trusted TLS certificate in your offline environment, you can configure the registry to use the certificate by following the [registry documentation for certificates](https://docs.docker.com/registry/deploying/#get-a-certificate).

If you do not have a TLS certificate (or you want to test first without one), you can configure Docker to treat your registry as an insecure registry.
You can do this according to the [Docker insecure registry documentation](https://docs.docker.com/registry/insecure/);
or, if you installed Docker with DeepOps, you can configure your list of insecure registries in the DeepOps configuration:

```
docker_insecure_registries:
- "registry-host:5000"
```


Loading images into the container registry
------------------------------------------

Once your registry is running and you've configured your hosts to access it, you can load additional images and push them to the offline registry:

```
$ docker load < /tmp/images/nvidia-cuda-11.1-devel-ubuntu20.04.tar
$ docker tag nvidia/cuda:11.1-devel-ubuntu20.04 registry-host:5000/nvidia/cuda:11.1-devel-ubuntu20.04
$ docker push registry-host:5000/nvidia/cuda:11.1-devel-ubuntu20.04
```
