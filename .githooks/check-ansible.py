#!/usr/bin/env python

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
            ansible_lint_paths_to_check.append(role_match.group(1))
    return ansible_lint_paths_to_check

print(get_changed_ansible_paths())
