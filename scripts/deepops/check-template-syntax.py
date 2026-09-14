#!/usr/bin/env python3
"""Parse every role template with Jinja and fail on syntax errors.

The template module renders these files through Jinja before installing them,
so a file that Jinja cannot parse breaks the play at deploy time even when the
file is perfectly valid in its own language. Shell scripts are the usual
victim: bash's array-length expansion contains a brace followed by a hash,
which opens a Jinja comment and aborts the render with "Missing end of comment
tag".

Only syntax is checked. Templates are parsed, never rendered, so no variables
are needed. Unknown filters (ternary, password_hash and other Ansible-provided
ones) raise TemplateAssertionError rather than a plain syntax error and are
reported as skipped, because plain Jinja has no way to know about them.
"""

import os
import sys

from jinja2 import Environment, FileSystemLoader
from jinja2.exceptions import TemplateAssertionError, TemplateSyntaxError

ROLES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "roles")


def main():
    roles_dir = os.path.normpath(ROLES)
    checked = skipped = 0
    failures = []

    for role in sorted(os.listdir(roles_dir)):
        templates = os.path.join(roles_dir, role, "templates")
        if not os.path.isdir(templates):
            continue
        env = Environment(loader=FileSystemLoader(templates), autoescape=True)
        for root, _, files in os.walk(templates):
            for name in sorted(files):
                rel = os.path.relpath(os.path.join(root, name), templates)
                try:
                    env.get_template(rel)
                except TemplateAssertionError as err:
                    # Ansible filter or test, unknown to plain Jinja.
                    skipped += 1
                    print(f"skip  {role}/{rel}: {err}")
                except TemplateSyntaxError as err:
                    failures.append((role, rel, err))
                else:
                    checked += 1

    print(f"\n{checked} templates parsed, {skipped} skipped, {len(failures)} failed")
    for role, rel, err in failures:
        print(f"FAIL  roles/{role}/templates/{rel}")
        print(f"      line {err.lineno}: {err.message}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
