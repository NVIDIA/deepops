NGINX-based Container Registry Caching Proxy
============================================

Overview
--------

Running container-based workloads on large compute clusters will generally require every node to pull a copy of the container image from the container registry.
However, many container images are very large, especially for deep learning or HPC development.
Pulling many copies of the same large container can therefore lead to saturating the connection to the registry, especially when the registry is only reachable over the outbound Internet connection.
If the registry is local, and the network connection is not the bottleneck, this can also lead to heavy load on the registry server itself!

In order to reduce this load, DeepOps includes a playbook to deploy a caching HTTP proxy based on [rpardini/docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy).
This proxy can be configured to cache container pulls from specific container registries, and caches containers on a per-layer basis.
Following the first pull from an upstream container registry, subsequent pulls will only fetch from the proxy, reducing the number of pulls that need to hit the upstream registry.


### Security considerations

Note that in order to successfully proxy HTTPS container registries, the caching proxy deployed by this playbook implements a "person-in-the-middle" HTTPS proxy.
This requires the proxy to use its own Certificate Authority (CA) to generate certificates which masquerade as the upstream registry.
The cluster nodes must then have the proxy's CA certificate added to their trusted store.

Because using this proxy requires that the nodes be configured to explicitly trust the proxy CA certificate, we believe this is a reasonable solution for a caching proxy.
However, those using this feature should ensure this mechanism fits their security policy, and may choose to implement additional logging or auditing around the use of this proxy.


Deploying the caching proxy 
---------------------------

### Configuration variables

The full list of variables used by the caching proxy role can be found in [roles/nginx-docker-registry-cache/defaults/main.yml](../../roles/nginx-docker-registry-cache/defaults/main.yml).

The following variables are the most common configuration you may want to adjust:

| Variable | Default value | Description |
| -------- | ------------- | ----------- |
| `nginx_docker_cache_image` | `"rpardini/docker-registry-proxy:0.6.1"` | Container image used to deploy the proxy |
| `nginx_docker_cache_registry_string` | `"quay.io k8s.gcr.io gcr.io nvcr.io"` | Space-separated list of registries to proxy |
| `nginx_docker_cache_manifests` | `"false"` | Flag to determine whether to cache image manifests |
| `nginx_docker_cache_manifest_default_time` | "1h" | If manifests are cached, time to cache them |
| `nginx_docker_cache_hostgroup` | `"cache"` | Ansible inventory host group where proxy is deployed |
| `nginx_docker_cache_dockerd_clients` | `true` | Flag to determine whether `dockerd` should be configured to use the proxy |
| `nginx_docker_cache_ca` | not configured by default | Specifies file paths for CA certificate and key, if you supply these yourself |


### Configuring a pre-generated CA

By default, the proxy will generate a CA certificate and key on its first run, and make the certificate available for clients to download.
This is usually the fastest way to get up and running, but means that if you fully re-deploy the proxy server, you may need to re-download the CA certificate on the clients.

If you choose, you can instead provide a pre-generated CA certificate and key and specify these be used.
A sample script for generating the key and certificate can be found in [scripts/nginx-docker-cache/gen-ca.sh](../../scripts/nginx-docker-cache/gen-ca.sh).

To specify the CA certificate and key which you wish to use, set the following variable:

```
nginx_docker_cache_ca:
- crt: "/path/to/ca.crt"
- key: "/path/to/ca.key"
```

This set of files will then be used for both the server and the clients.

 
### Server deployment

To deploy the proxy server with the default configuration, add the host(s) where you wish to run the proxy to the `cache` hostgroup in inventory.
Then run:

```
ansible-playbook -l cache playbooks/container/nginx-docker-registry-cache-server.yml
```


### Configuring Docker clients

To configure client nodes using Docker for container pulls, ensure `nginx_docker_cache_dockerd_clients` is set to `true`, then run:

```
ansible-playbook -l <nodes> playbooks/container/nginx-docker-registry-cache-client.yml
```

### Configuring Enroot clients

To configure client nodes using Enroot for container pulls, add the following line to the `enroot_config` variable:

```
https_proxy=http://<proxy-hostname>:3128/
```

Where `<proxy_hostname>` is the name of the host where you're running the proxy.

Then run:

```
ansible-playbook -l <nodes> playbooks/container/nginx-docker-registry-cache-client.yml
ansible-playbook -l <nodes> playbooks/container/pyxis.yml
```
