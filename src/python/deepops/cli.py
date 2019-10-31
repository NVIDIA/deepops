# -*- coding: utf-8 -*-
from __future__ import absolute_import


"""Console script for deepops."""
import sys
import click

from .repo import clone_repo, local_repo_path
from .deps import run_deepops_setup
from .ansible import (
    make_ansible_inventory_file,
    run_ansible_playbook,
    AnsibleFailedError,
)


@click.group()
def main(args=None):
    """GPU infrastructure and automation tools"""
    return 0


#######################################################################
# Repository management commands
#######################################################################


@main.group()
def repo(args=None):
    """Commands for managing the local copy of the DeepOps repo"""
    return 0


@repo.command()
@click.option("--path", default=None)
@click.option(
    "--remote", default="https://github.com/NVIDIA/deepops", show_default=True
)
@click.option("--tag", default="master", show_default=True)
@click.option("--force", is_flag=True)
def clone(path, remote, tag, force):
    """Clone DeepOps repository locally"""
    clone_repo(repo_path=path, remote=remote, force=force, tag=tag)


@repo.command()
def show_path():
    """Show configured repository path"""
    click.echo(local_repo_path())


#######################################################################
# Install commands
#######################################################################


@main.group()
def install(args=None):
    """Commands for installing DeepOps components"""
    return 0


@install.command(name="deepops-dependencies")
def deepops_deps():
    click.echo("Installing DeepOps repo dependencies")
    run_deepops_setup()


@install.command(name="nvidia-driver")
@click.option("--debug", is_flag=True)
@click.option("--dry-run", is_flag=True)
def nvidia_driver(debug, dry_run):
    """Install NVIDIA driver"""
    click.echo("Run Ansible to install NVIDIA driver")
    inv_file = make_ansible_inventory_file()
    if debug:
        click.echo("inventory file: {}".format(inv_file))
    if dry_run:
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/nvidia-driver.yml".format(
                local_repo_path()
            )
        )
        return
    try:
        run_ansible_playbook("playbooks/nvidia-driver.yml", inv_file)
    except AnsibleFailedError:
        click.echo(
            "Ansible run failed, but this is expected if you are running \n"
            "on localhost and the playbook wants to reboot to install the \n"
            "driver.\n\n"
            "If the last attempted task was a reboot, you should reboot \n"
            "this host and run again to finish."
        )


@install.command(name="nvidia-docker")
@click.option("--debug", is_flag=True)
@click.option("--dry-run", is_flag=True)
def nvidia_docker(debug, dry_run):
    """Install Docker and nvidia-docker"""
    click.echo("Run Ansible to install Docker and nvidia-docker")
    inv_file = make_ansible_inventory_file()
    if debug:
        click.echo("inventory file: {}".format(inv_file))
    if dry_run:
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/docker.yml".format(
                local_repo_path()
            )
        )
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/nvidia-docker.yml".format(
                local_repo_path()
            )
        )
        return
    run_ansible_playbook("playbooks/docker.yml", inv_file)
    run_ansible_playbook("playbooks/nvidia-docker.yml", inv_file)


@install.command(name="k8s")
@click.option("--debug", is_flag=True)
@click.option("--dry-run", is_flag=True)
def kubespray_install(debug, dry_run):
    """Install Kubernetes using Kubespray"""
    click.echo("Run Ansible to install Kubernetes")
    if not dry_run:
        if not click.confirm(
            "This will install a single-node Kubernetes cluster on the local "
            "machine. Are you sure you want to continue?"
        ):
            return 1
    host_groups = {
        "all": ["localhost    ansible_connection=local"],
        "kube-master": ["localhost"],
        "etcd": ["localhost"],
        "kube-node": ["localhost"],
        "k8s-cluster:children": ["kube-master", "kube-node"],
    }
    inv_file = make_ansible_inventory_file(host_groups)
    if debug:
        click.echo("inventory file: {}".format(inv_file))
    if dry_run:
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/k8s-cluster.yml".format(
                local_repo_path()
            )
        )
        return 0
    run_ansible_playbook("playbooks/k8s-cluster.yml", inv_file)


@install.command(name="slurm")
@click.option("--debug", is_flag=True)
@click.option("--dry-run", is_flag=True)
def slurm_install(debug, dry_run):
    """Install Slurm"""
    click.echo("Run Ansible to install Slurm")
    if not dry_run:
        if not click.confirm(
            "This will install a single-node Slurm cluster on the local "
            "machine. Are you sure you want to continue?"
        ):
            return 1
    host_groups = {
        "all": ["localhost    ansible_connection=local"],
        "slurm-master": ["localhost"],
        "slurm-node": ["localhost"],
        "slurm-cluster:children": ["slurm-master", "slurm-node"],
    }
    inv_file = make_ansible_inventory_file(host_groups)
    if debug:
        click.echo("inventory file: {}".format(inv_file))
    if dry_run:
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/slurm-cluster.yml".format(
                local_repo_path()
            )
        )
        return 0

    # For a localhost Slurm cluster, disable prolog/epilog
    extra_flags = ["--extra-vars", "'{slurm_enable_prolog_epilog:false}'"]

    try:
        run_ansible_playbook(
            "playbooks/slurm-cluster.yml", inv_file, extra_flags=extra_flags
        )
    except AnsibleFailedError:
        click.echo(
            "Ansible run failed, but this is expected if you are running \n"
            "on localhost and the playbook wants to reboot.\n\n"
            "If the last attempted task was a reboot, you should reboot \n"
            "this host and run again to finish."
        )


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
