#!/usr/bin/env python
"""
Get a list of changed python scripts that are staged for commit.
Run shellcheck on only those files.
"""


from __future__ import print_function
import subprocess
import re
import sys


def get_changed_paths():
    git_diff = subprocess.check_output("git diff --name-only --cached".split())
    paths = []
    for f in git_diff.split("\n"):
        # Add playbook files
        if re.match(r".*(\.py)$", f):
            paths.append(f)
    return paths


def run_lint(paths):
    cmd = ["pylint", "-rn", "-sn", "-d", "R,C"] + paths
    return subprocess.call(cmd)


if __name__ == "__main__":
    changed = get_changed_paths()
    if len(changed) > 0:
        sys.exit(run_lint(changed))
