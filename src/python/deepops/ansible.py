import os
import subprocess
from tempfile import mkstemp
from socket import gethostname

from .repo import local_repo_path


class AnsibleFailedError(Exception):
    pass


def make_host_groups_for_local(hostname=None, added_groups=[]):
    """
    Create a host_groups variable which includes the local machine in all
    provided groups
    """
    if not hostname:
        localhost = gethostname()
    host_groups = {"all": ["{}    ansible_connection=local".format(localhost)]}
    for g in added_groups:
        host_groups[g] = [localhost]
    return host_groups


def make_ansible_inventory_file(host_groups=None):
    if not host_groups:
        host_groups = make_host_groups_for_local()
    fd, fname = mkstemp()
    with open(fname, "w") as f:
        for g in host_groups.keys():
            f.write("[{}]\n".format(g))
            for l in host_groups[g]:
                f.write(l + "\n")
    os.close(fd)
    return fname


def run_ansible_playbook(playbook, inventory_file, repo_path=None, extra_flags=[]):
    if not repo_path:
        repo_path = local_repo_path()
    command = ["ansible-playbook", "-i", inventory_file] + extra_flags + [playbook]
    original_directory = os.getcwd()
    os.chdir(repo_path)
    rc = subprocess.call(command)
    os.chdir(original_directory)
    if rc != 0:
        raise AnsibleFailedError("Playbook run failed: {}".format(" ".join(command)))
