# -*- coding: utf-8 -*-

"""Console script for deepops."""
import sys
import click

from .repo import clone_repo, local_repo_path
from .deps import run_deepops_setup


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
def nvidia_driver():
    click.echo("Install NVIDIA driver")


@install.command(name="nvidia-docker")
def nvidia_docker():
    click.echo("Install nvidia-docker")


@install.command(name="k8s")
def kubespray_install():
    click.echo("Install Kubernetes using Kubespray")


@install.command(name="slurm")
def slurm_install():
    click.echo("Install Slurm")


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
