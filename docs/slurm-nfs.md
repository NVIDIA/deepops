Slurm cluster configuration for NFS filesystems
===============================================

Slurm clusters typically depend on the presence of one or more shared filesystems, mounted on all the nodes in the cluster.
Having a shared filesystem simplifies software installation and provides a common working space for user jobs,
and many common HPC applications depend on the presence of such a filesystem.

Our default configuration in DeepOps achieves this by configuring the Slurm control/login node as an NFS server,
and the compute nodes as clients of the NFS server.


## Configuring NFS shares from the Slurm control node

By default, we configure two NFS exports from the control node to the compute nodes:

* `/home`: The user home directory space is shared across all nodes in the cluster.
    This is a common pattern on most HPC clusters.
* `/sw`: This directory provides a separate directory for installing software that needs to be built from source.
    In most clusters this will be an admin-only area, not writeable by regular users, but this is a choice for the cluster admin.

If you would like to make changes to that configuration, you can do so be setting the following variables.

### Exports from the Slurm control node

```
nfs_exports:
- path: "<absolute path of exported directory on control node>"
  options: "<ips allowed to mount>(<options for the NFS export>)"
- path: "<absolute path of another exported directory>"
  options: "<ips allowed to mount>(<options for the NFS export>)"
...
```

You can add as many additional exports to the list as you wish, configuring each appropriately.

The `options` field for each export, which specifies the IPs allowed to mount these exports and the options for the export, follows the format of the NFS `/etc/exports` file.
For documentation on the available NFS export options, see the manpages for your Linux distribution: `man 5 exports`.


### NFS mounts on the clients

```
nfs_mounts:
- mountpoint: "<absolute path of directory to mount share on clients>"
  server: "<hostname of NFS server>"
  path: "<path of the export from the server>"
  options: "<nfs mount options>"
- mountpoint: "<absolute path of another directory to mount share on clients>"
  server: "<hostname of NFS server>"
  path: "<path of the export from the server>"
  options: "<nfs mount options>"
...
```

As above, you can add as many additional mounts to the list as you wish.

The `options` field for each mount specifies the NFS options used to mount the filesystem.
For the available NFS options, see the manpages for your Linux distribution: `man 5 nfs`.


## Configuring a separate NFS server

If your site already has an NFS server, you may wish to use your existing server rather than setting up the Slurm control node to serve NFS.
To configure DeepOps to use your existing server, you should set the following configuration values:

* Set `slurm_enable_nfs_server` to `false`

* Set `nfs_client_group` to `"slurm-cluster"`

* Configure the `nfs_mounts` variable as shown below, repeating the list item for each NFS export

```
nfs_mounts:
- mountpoint: "<absolute path of directory to mount share on clients>"
  server: "<hostname of NFS server>"
  path: "<path of the export from the server>"
  options: "<nfs mount options>"
- mountpoint: "<absolute path of another directory to mount share on clients>"
  server: "<hostname of NFS server>"
  path: "<path of the export from the server>"
  options: "<nfs mount options>"
...

```

## Disabling NFS

If you want to disable the use of any NFS mounts, or want to configure NFS yourself outside of DeepOps, set the following variables:

* Set `slurm_enable_nfs_server` to `false`
* Set `slurm_enable_nfs_client_nodes` to `false`
