# Recommendations for deploying Slurm on large clusters

The default configuration for a DeepOps Slurm cluster is well-suited for fast deployment with a minimum of hardware and little user configuration.
This is very useful for small clusters and getting online quickly, but doesn't always fit when deploying larger clusters at scale.

When building a larger cluster, there are several changes to the default Slurm workflow which are helpful to consider.
These include:

* [Cache container pulls from external registries](#cache-container-pulls-from-external-registries)
* [Manually generate static files for cluster-wide configuration](#manually-generate-static-files-for-cluster-wide-configuration)
* [Separate specific functions on different hardware](#separate-specific-functions-on-different-hardware)

## Cache container pulls from external registries

Running container-based workloads on large compute clusters will generally require every node to pull a copy of the container image from the container registry.
However, many container images are very large, especially for deep learning or HPC development.
Pulling many copies of the same large container can therefore lead to saturating the connection to the registry, especially when the registry is only reachable over the outbound Internet connection.
If the registry is local, and the network connection is not the bottleneck, this can also lead to heavy load on the registry server itself!

DeepOps provides support for deploying a caching proxy to reduce pulls from upstream container registries.
For more information, see the doc on the [NGINX-based container registry proxy](../container/nginx-docker-cache.md).


## Manually generate static files for cluster-wide configuration

Some of the configuration files used in a Slurm cluster require information about all the nodes in the cluster.
This information may include the names of all the hosts in the cluster, their IP addresses, or other facts about the hardware.
Two examples of this are the `/etc/hosts` file and the `slurm.conf` file.

When DeepOps generates these files, it does so by contacting every host, gathering data about how they're configured, and publishing all the collected information to every host where the files are being generated.
This works well on small clusters, but it can be slow or unreliable on larger clusters, where it's not uncommon for one or more hosts to be down or unreachable.
When running on even 10 hosts, these files can be a frequent source of Ansible failures.

In these cases, it may make sense to manually generate static configuration files, and configure DeepOps to use the static files instead of generating them on the fly.
For most of these files, DeepOps provides Ansible variables which you can use to set the source path for a static version of the file.

These include:

| File | Ansible variable | Function | How to configure |
| ---- | ---------------- | -------- | ---------------- |
| `/etc/hosts` | `hosts_file_src` | List of hosts and IP addresses in the cluster | [hosts file manual](https://man7.org/linux/man-pages/man5/hosts.5.html) |
| `/etc/slurm/slurm.conf` | `slurm_conf_template` | Slurm scheduler configuration | [Slurm configurator](https://slurm.schedmd.com/configurator.easy.html) |
| `/etc/nhc/nhc.conf` | `nhc_config_template` | Node Health Check configuration | [NHC documentation](https://github.com/mej/nhc/blob/master/README.md) |
| `/etc/prometheus/endpoints/node-exporter.yml` | `node_exporter_conf_template` | Prometheus endpoints for node-exporter | [Sample targets config](https://prometheus.io/docs/prometheus/latest/getting_started/#configure-prometheus-to-monitor-the-sample-targets) |
| `/etc/prometheus/endpoints/dcgm-exporter.yml` | `nvidia_dcgm_exporter_conf_template` | Prometheus endpoints for dcgm-exporter | [Sample targets config](https://prometheus.io/docs/prometheus/latest/getting_started/#configure-prometheus-to-monitor-the-sample-targets) |
| `/etc/prometheus/endpoints/slurm-exporter.yml` | `slurm_exporter_conf_template` | Prometheus endpoints for slurm-exporter | [Sample targets config](https://prometheus.io/docs/prometheus/latest/getting_started/#configure-prometheus-to-monitor-the-sample-targets) |

In many cases, a good way to get started with one of these files is to run DeepOps once, find the generated file, and then use it as a starting point for your static file.
 

## Separate specific functions on different hardware

To minimize hardware requirements for cluster management services, DeepOps deploys a single Slurm head node by default.
This head node provides multiple services to the rest of the cluster, including:

* Slurm controller and database
* NFS shared filesystem
* User logins
* Monitoring services

However, on larger clusters, it often makes sense to run these functions on multiple separate machines.
DeepOps provides support for running these functions on separate machines using a combination of changes to the Ansible inventory file, and setting Ansible variables to specify where these functions should run.

### Separate login nodes

The most common case in which you will want to add additional service nodes, is to separate the user login node from the Slurm controller node.
This provides a level of isolation between user activity and the Slurm cluster services, so that user activity is less likely to negatively impact the cluster services.
Multiple login nodes may also be deployed to allow you to provide services to a larger number of users, or for high availability.

Separate user login nodes need to have the Slurm packages installed, but should not run any Slurm services such as `slurmd` or `slurmctld`.
In DeepOps, this can be accomplished by adding these machines to the `slurm-cluster` inventory group, but not to the `slurm-master` or `slurm-node` groups.

For example, the following inventory file can be used to set up a cluster with one controller, two login nodes, and two compute nodes.

```
[slurm-master]
slurm-controller01

[slurm-login]
slurm-login01
slurm-login02

[slurm-node]
slurm-compute01
slurm-compute02

[slurm-cluster:children]
slurm-master
slurm-login
slurm-node
```

### Separate monitoring node

| Variable | Default value |
| -------- | ------------- |
| `slurm_monitoring_group` | `slurm-master` |

The Slurm monitoring services are deployed to whichever hosts are specified in the variable `slurm_monitoring_group`.
This should be the name of an Ansible inventory hostgroup with one node.
In the default configuration, we run the monitoring services on the Slurm controller node.

Note that in order to correctly monitor Slurm, the monitoring node must have Slurm installed and have access to the cluster.
As with the login nodes, the easiest way to do this is to add the monitoring node to the `slurm-cluster` group, but not to `slurm-master` or `slurm-node`.

So, for example, the following inventory file should allow a monitoring node to be deployed:

```
[slurm-master]
slurm-controller01

[slurm-monitoring]
slurm-mon01

[slurm-node]
slurm-compute01
slurm-compute02

[slurm-cluster:children]
slurm-master
slurm-monitoring
slurm-node
``` 

With the following variable configured:

```
slurm_monitoring_group: "slurm-monitoring"
```

### Separate NFS server

Our Slurm cluster deployment relies on a shared NFS filesystem across the cluster.
One machine is used to run the NFS server, and all other machines in the cluster are NFS clients.
We specify these machines using these variables:

| Variable | Default value |
| -------- | ------------- |
| `nfs_server_group` | `slurm-master[0]` |
| `nfs_client_group` | `slurm-master[1:],slurm-node` |

To change this topology, you can change these variables to run the NFS server and client playbooks on a different set of hosts.

### Example: NFS on login node, with separate Slurm controller

Inventory:

```
[slurm-master]
slurm-controller01

[slurm-login]
slurm-login01

[slurm-node]
slurm-compute01
slurm-compute02

[slurm-cluster:children]
slurm-master
slurm-login
slurm-node
```

Variables:

```
nfs_server_group: "slurm-login[0]"
nfs_client_group: "slurm-master,slurm-node"
```

#### Example: NFS on separate machine not in the Slurm cluster 

In many cases, large deployments will have pre-existing NFS filesystems available which DeepOps should mount.
In this case, we can choose not to deploy an NFS server, but instead simply configure all nodes as clients.

In order to disable NFS server deployment, you should set:

```
slurm_enable_nfs_server: false
```

Then, to configure all hosts to mount from one or more external servers, configure:

```
nfs_client_group: "slurm-cluster"

nfs_mounts:
- mountpoint: /home
  server: external-nfs-server-01.example.com
  path: /export/home
  options: async,vers=3
- mountpoint: /shared
  server: external-nfs-server-02.example.com
  path: /export/shared
  options: async,vers=3
```

Where the parameters to `nfs_mounts` should be adjusted based on your local environment.
