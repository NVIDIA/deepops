import os
import subprocess
from deepops import repo, config


def run_deepops_setup():
    repo.clone_repo()
    repo_root = repo.local_repo_path()
    if not os.path.isfile("{}/scripts/setup.sh".format(repo_root)):
        raise Exception("Could not find DeepOps setup script")
    subprocess.call(["{}/scripts/setup.sh".format(repo_root)])
