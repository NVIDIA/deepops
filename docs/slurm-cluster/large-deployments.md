# Deploying Slurm on large clusters

To minimize hardware requirements for cluster management services, DeepOps deploys a single Slurm head node by default.
This head node provides multiple servies to the rest of the cluster, including:

* Slurm controller and database
* NFS shared filesystem
* User logins
* Monitoring services

However, on larger clusters, it often makes sense to run these functions on multiple separate machines.
DeepOps provides support for running these functions on separate machines using a combination of changes to the Ansible inventory file, and setting Ansible variables to specify where these functions should run.

## Separate login nodes

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

## Separate monitoring node

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

## Separate NFS server

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

### Example: NFS on separate machine not in the Slurm cluster 

In many cases, large deployments will have pre-existing NFS filesystems available which DeepOps should mount.
In this case, we can choose not to deploy an NFS server, but instead simply configure all nodes as clients.

In order to disable NFS server deployment, you should set:

```
slurm_enable_nfs_server: false
```

Then, to configure all hosts to mount from one or more external serveris, configure:

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
