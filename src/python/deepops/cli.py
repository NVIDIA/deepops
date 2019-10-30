# -*- coding: utf-8 -*-

"""Console script for deepops."""
import sys
import click


@click.group()
def main(args=None):
    """Top-level group for cli"""
    return 0


#######################################################################
# Install commands
#######################################################################

@main.group()
def install(args=None):
    """Commands for installing DeepOps components"""
    return 0


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
