import os
import subprocess
from .repo import clone_repo, local_repo_path


def run_deepops_setup():
    clone_repo()
    repo_root = local_repo_path()
    if not os.path.isfile("{}/scripts/setup.sh".format(repo_root)):
        raise Exception("Could not find DeepOps setup script")
    subprocess.call(["{}/scripts/setup.sh".format(repo_root)])
