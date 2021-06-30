Configuring DeepOps
===================

## The DeepOps configuration directory

When you first clone the DeepOps repository and run `scripts/setup.sh`, one of the first things that the setup script does is copy the [`config.example` directory](../../config.example) to a new directory called `config`.
This directory is your DeepOps configuration directory, and contains several files that govern the behavior of the Ansible playbooks used by DeepOps.

In particular, this directory includes:

- `config/inventory`: The [Ansible inventory file](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html) that lists the hosts in your cluster
- `config/group_vars/all.yml`: An Ansible [variables file](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html) that contains variables we expect to work for all hosts
- `config/group_vars/k8s-cluster.yml`: Variables specific to deploying Kubernetes clusters
- `config/group_vars/slurm-cluster.yml`: Variables specific to deploying Slurm clusters
- `config/requirements.yml`: An Ansible Galaxy [requirements file](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html#installing-roles-and-collections-from-the-same-requirements-yml-file) that contains a list of custom Collections and Roles to install. Collections and Roles required by DeepOps are stored in a separate `roles/requirements.yml` file, which should not be modified.

It's expected that most DeepOps deployments will make changes to these files!
The inventory file will be different for every cluster;
but we also expect that most people will make changes to the Ansible variables that determine how DeepOps behaves.
While the example configuration contains good defaults (in our opinion!), every cluster is different, and a lot of the features in DeepOps can be configured or are optional.

For example, you may choose to:

- Enable or disable optional features, such as installing a container registry
- Change the version of software being installed, such as the Slurm version
- Or change the download URL used for a software install, if you want to point to a different mirror

However, unless you're developing changes to DeepOps itself, you should never have to make changes *outside your configuration directory*.
(If you do, that's a sign that we haven't made our playbooks configurable enough, and you should open an issue or PR to fix that!)

Ideally, we expect that all customizations for a specific cluster should be made in the configuration directory for that cluster.
There are a few exceptions to this in the [example workloads directory](../../workloads), but in most cases it should be possible to copy these to your config directory to manage with the rest of your configuration.


## Modifying the Ansible inventory

Every cluster deployed with DeepOps will have its own [Ansible inventory file](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html).
This file defines the list of hosts that are in your DeepOps cluster, and has several sections depending on how your cluster is configured.

In general, we expect that there will always be a section labeled `[all]` that contains a list of every host in the cluster.
If you need to supply the IP addresses of your hosts, you will usually specify those IPs here as well.
For example:

```
[all]
my-cluster-controller      ansible_host=10.0.0.1
my-cluster-compute-01      ansible_host=10.0.0.2
my-cluster-compute-02      ansible_host=10.0.0.3
```

(Note that, by default, DeepOps will set the hostname of these machines to match the inventory hostname!
If you don't want this, you can set `deepops_set_hostname: false` using the instructions in [the next section](#modifying-ansible-variables).)

The example DeepOps inventory also includes groups for the different components of Kubernetes clusters (`kube-master`, `etcd`, and `kube-node`),
and groups for the different components of Slurm clusters (`slurm-master` and `slurm-node`).
These groups are used by DeepOps to determine which playbooks run on which nodes for each type of cluster,
and you should add nodes to these groups based on how you want to lay out your cluster.
For example:

```
[slurm-master]
my-cluster-controller

[slurm-node]
my-cluster-compute-01
my-cluster-compute-02
```

If you want to further sub-divide your cluster, or target particular hosts with playbooks, you can add other inventory groups to this file!
For example, if you have a host that you will use as a separate NFS server, you may want to create an `nfs-server` group and only run the [NFS server playbook](../../playbooks/generic/nfs-server.yml) on that host.
You can restrict the hosts that will run an Ansible playbook using the `--limit` or `-l` flag, e.g.:

```
ansible-playbook -l nfs-server playbooks/generic/nfs-server.yml
```

For more information on using Ansible inventory files, we recommend reading the [Ansible documentation](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html).


## Modifying Ansible variables

After the inventory file, the next most common customization is to modify the Ansible variables used for your cluster.
These variables are included in the various files under [`config/group_vars`](../../config.example/group_vars).


### Optional features

DeepOps uses Ansible variables extensively as boolean "flags", to turn on and off optional features.
In different situations, you may want to enable features that DeepOps doesn't set up by default, or turn off features that are enabled by default.

For example, the [slurm-cluster playbook](../../playbooks/slurm-cluster.yml) automatically deploys a caching container registry on the login node by default.
This is useful if you plan to use containers on your cluster, but you might not want to do this if you do all your development outside containers!
This feature can be disabled by setting `slurm_enable_container_registry: false` in your DeepOps configuration.


### Role parameters

Many of the Ansible roles in DeepOps are parameterized, allowing you to change values such as component versions, download URLs, or filesystem paths.

For example, the [OpenMPI role](../../roles/openmpi) installs OpenMPI 4.0.3 by default.
However, some applications still don't work with more recent versions of OpenMPI, and you may want to install OpenMPI 3.1.6 instead.
You can do this with an Ansible variable by setting `openmpi_version: "3.1.6"`.


### Finding variables to change

At this point, the natural question is, "where can I find what variables are available to change?"
The [example configuration files](../../config.example/group_vars) list the most common parameters you may want to change,
as well as specifying their default values.
In particlar, these files should contain all of the flags that enable or disable features in [k8s-cluster.yml](../../playbooks/k8s-cluster.yml) or [slurm-cluster.yml](../../playbooks/slurm-cluster.yml).

If you're interested in customizing the behavior of a particular Ansible role further, you may also want to check the `defaults` directory for that role.
This contains the default values of the variables included with the role itself, and may contain variables that aren't listed in the example configuration.
However, you can override these values by adding them to your DeepOps configuration files.


### Which file should my variables go in?

**Group variables** are applied to all the hosts in an Ansible inventory group.
These variables are specified in files named for the inventory group used, in the `config/group_vars` directory:

```
config/group_vars/
├── all.yml
├── k8s-cluster.yml
├── netapp-trident.yml
└── slurm-cluster.yml
```

So, for example, variables in the `all.yml` file will apply to all the hosts in your inventory;
but variables in the `slurm-cluster.yml` file will only be used for hosts in the `slurm-cluster` inventory group.
If you add more inventory groups, you can add files to `group_vars` to apply variables to them.

**Host variables** are variables that should only be used for a specific host.
This kind of variable should be used for parameters that vary across each machine,
such as IP addresses,
or test configurations,
such as installing a different version of the NVIDIA driver on a host where you're testing an upgrade.
These variables go in files named for each host in the `host_vars` directory:

```
config/host_vars/
└── gpu01
```

The variables in `host_vars/gpu01` would only be applied for a host named `gpu01`.


## Adding custom playbooks

In the process of setting up your cluster, you may want to write your own Ansible playbooks for features that DeepOps doesn't include!

For example, DeepOps doesn't (yet) include a playbook for installing the classic Linux game [Pingus](https://pingus.seul.org/).
If you wrote an Ansible playbook for installing Pingus on your cluster (to give your users a way to [entertain themselves while their code compiles](https://xkcd.com/303/)),
you would put it in your `config/playbooks` directory:

```
config/playbooks/
└── pingus.yml
```

This playbook can then be run with Ansible like any other DeepOps playbook:

```
ansible-playbook config/playbooks/pingus.yml
```

And can make use of variables in your `config` directory like other playboks.


## Managing your configuration directory in Git

We recommend creating a separate Git repository for managing your cluster configuration, so that you can track changes to your cluster independently of DeepOps changes and upgrades.
(The DeepOps [`.gitignore` file](../../.gitignore) is set up to faciliate this by ignoring directories that start with the string `config`, except for `config.example`.)

A good practice is to start a new Git repository by copying the example configuration:

```
$ cp -R config.example/ config/
$ cd config
$ git init
$ git commit -am "Start from the example configuration"
```

And then pushing this repository to a remote Git host, such as Github:

```
$ cd config.my-cluster/
$ git remote add origin <your-git-remote>
$ git push -u origin main
```

Once you have a repository set up, you can use it to track changes as you configure your cluster.
For example, if you change the version of Slurm being installed:

```
$ cd config.my-cluster/group_vars/

# Edit your Slurm configuration to upgrade to version 20.11
$ vim slurm-cluster.yml

$ git add slurm-cluster.yml
$ git commit -m "Update cluster to Slurm 20.11"
```


## Using multiple configuration directories for separate clusters

If you're running multiple clusters, you can keep their configuration in separate configuration directories within the same DeepOps repository clone:

```
config.cluster-0
└── group_vars
config.cluster-1
├── group_vars
└── host_vars
config.cluster-2
├── group_vars
├── host_vars
└── playbooks
```

These configuration directories can each have their own inventory files, Ansible variables, and playbooks.

You can then run Ansible for each of the clusters independently by specifying the inventory file on the command line:

```
ansible-playbook -i config.cluster-1/inventory playbooks/slurm-cluster.yml
```
