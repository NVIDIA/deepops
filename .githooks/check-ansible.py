#!/usr/bin/env python
"""
Get a list of Ansible playbooks and roles that have changes staged in Git.
Run ansible-lint on only those playbooks and roles.
"""


from __future__ import print_function
import subprocess
import re


def get_changed_ansible_paths():
    """
    Get a list of playbook files and role directories that are staged for commit
    """
    git_diff = subprocess.check_output("git diff --name-only --cached".split())
    ansible_lint_paths_to_check = []
    for f in git_diff.split("\n"):
        # Add playbook files
        if re.match(r"^playbooks/.*(yml|yaml)$", f):
            ansible_lint_paths_to_check.append(f)
        # Add role directories
        role_match = re.match(r"^roles/(\w+)/.*", f)
        if role_match:
            ansible_lint_paths_to_check.append(
                "roles/{}".format(role_match.group(1)))
    return ansible_lint_paths_to_check


def run_ansible_lint(paths):
    cmd = ["ansible-lint"] + paths
    subprocess.call(cmd)


if __name__ == "__main__":
    paths = get_changed_ansible_paths()
    print(paths)
    if len(paths) > 0:
        run_ansible_lint(paths)
