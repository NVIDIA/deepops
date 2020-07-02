# -*- coding: utf-8 -*-
from __future__ import absolute_import


"""Console script for deepops."""
import sys
import click
import os

from .repo import clone_repo, local_repo_path
from .deps import run_deepops_setup
from .ansible import (
    make_ansible_inventory_file,
    make_host_groups_for_local,
    make_ansible_vars_file,
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
@click.option("--tag", default="20.06", show_default=True)
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
    run_deepops_setup()
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
    run_deepops_setup()
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
        run_deepops_setup()
    host_groups = make_host_groups_for_local(
        added_groups=["kube-master", "etcd", "kube-node"]
    )
    host_groups["k8s-cluster:children"] = ["kube-master", "kube-node"]
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


def slurm_extra_vars():
    return {
        "slurm_enable_prolog_epilog": False,
        "slurm_clear_old_prolog_epilog": True,
        "slurm_allow_ssh_user": [os.environ["USER"]],
        "slurm_build_dir": "/opt/deepops/slurm-build",
    }


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
        run_deepops_setup()

    host_groups = make_host_groups_for_local(
        added_groups=["slurm-master", "slurm-node"]
    )
    host_groups["slurm-cluster:children"] = ["slurm-master", "slurm-node"]
    inv_file = make_ansible_inventory_file(host_groups)
    vars_file = make_ansible_vars_file(ansible_vars=slurm_extra_vars())
    if debug:
        click.echo("inventory file: {}".format(inv_file))
        click.echo("vars file: {}".format(vars_file))

    if dry_run:
        click.echo(
            "Would have run ansible-playbook with {}/playbooks/slurm-cluster.yml".format(
                local_repo_path()
            )
        )
        return 0

    try:
        run_ansible_playbook(
            "playbooks/slurm-cluster.yml", inv_file, extra_vars_file=vars_file
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