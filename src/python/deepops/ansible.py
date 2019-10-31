import os
import subprocess
from tempfile import mkstemp

from .repo import local_repo_path


def make_ansible_inventory_file(host_groups=None):
    if not host_groups:
        host_groups = {"all": ["localhost    ansible_connection=local"]}
    fd, fname = mkstemp()
    with open(fname, "w") as f:
        for g in host_groups.keys():
            f.write("[{}]\n".format(g))
            for l in host_groups[g]:
                f.write(l + "\n")
    os.close(fd)
    return fname


def run_ansible_playbook(playbook, inventory_file, repo_path=None):
    if not repo_path:
        repo_path = local_repo_path()
    command = ["ansible-playbook", "-i", inventory_file, playbook]
    original_directory = os.getcwd()
    os.chdir(repo_path)
    rc = subprocess.call(command)
    os.chdir(original_directory)
    if rc != 0:
        raise Exception("Command failed: {}".format(" ".join(command)))
