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

It's expected for most DeepOps deployments to make changes to these files!
The inventory file will be different for every cluster;
but we also expect that most people will make changes to the Ansible variables that determine how DeepOps behaves.
While the example configuration contains good defaults (in our opinion!), every cluster is different, and a lot of the features in DeepOps can be configured or are optional.

For example, you may choose to:

- Enable or disable optional features, such as installing a container registry;
- Change the version of software being installed, such as the Slurm version;
- Or change the download URL used for a software install, if you want to point to a different mirror

However, unless you're developing changes to DeepOps itself, you should never have to make changes *outside your configuration directory*.
(If you do, that's a sign that we haven't made our playbooks configurable enough, and you should open an issue or PR to fix that!)
Ideally, we expect that all customizations for a specific cluster should be made in the configuration directory for that cluster.


## Modifying the Ansible inventory



## Modifying Ansible variables

The most common change to the DeepOps

## Adding custom playbooks


## Using multiple configuration directories


## Managing your configuration in Git


