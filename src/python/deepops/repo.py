import os
import subprocess
import shutil
from pathlib import Path

import click
from deepops import config


def local_repo_path():
    """Determine correct local path for DeepOps repository"""
    deepops_config = config.get_config()
    if "repo" in deepops_config.sections() and deepops_config.get("repo", "path"):
        return deepops_config.get("repo", "path")
    if os.environ.get("XDG_DATA_HOME"):
        return "{}/deepops/repo".format(os.environ.get("XDG_DATA_HOME"))
    if os.environ.get("HOME"):
        return "{}/.local/share/deepops/repo".format(os.environ.get("HOME"))
    else:
        raise Exception("Cannot determine path for deepops repo")


def check_repo_exists(repo_path=None):
    """Check if DeepOps repo has been cloned"""
    if not repo_path:
        repo_path = local_repo_path()
    if os.path.isdir("{}/.git".format(repo_path)):
        return True
    return False


def _ensure_parent_exists(path):
    p = Path(path)
    if not os.path.isdir(p.parent):
        os.makedirs(p.parent)


def clone_repo(
    repo_path=None,
    remote="https://github.com/NVIDIA/deepops",
    force=False,
    tag="master",
):
    """Clone the DeepOps repo locally"""
    if not repo_path:
        repo_path = local_repo_path()
    if check_repo_exists(repo_path) and (not force):
        return
    if force:
        shutil.rmtree(repo_path)
    command = ["git", "clone", "-b", tag, remote, repo_path]
    try:
        _ensure_parent_exists(repo_path)
        rc = subprocess.call(command)
    except FileNotFoundError:
        click.echo("Could not find 'git' command")
    if rc != 0:
        click.echo("Command failed: {}".format(" ".join(command)))
