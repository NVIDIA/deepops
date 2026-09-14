#!/usr/bin/env python3
"""Render one Slurm prolog/epilog template so the tests exercise the deployed form.

These files are Jinja templates, so they cannot be run -- or even parsed by
`bash -n` -- as they sit in the repository. Testing a hand-trimmed copy would
test something the cluster never runs, so the harness renders first and runs
the result.
"""
import sys

from jinja2 import Environment, FileSystemLoader, StrictUndefined

# Values a deployment supplies. Kept here rather than in the shell harness so
# that a template referencing an unset variable fails loudly (StrictUndefined)
# instead of rendering an empty string and changing what is under test.
VARS = {
    "slurm_config_dir": "/etc/slurm",
    "slurm_install_prefix": "/usr",
    "enroot_runtime_path": "/run/enroot/user-$(id -u)",
    "enroot_cache_path": "/var/lib/enroot-cache/user-$(id -u)",
    "enroot_data_path": "/tmp/enroot-data/user-$(id -u)",
}


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: render.py <template-path> <output-path>")

    template_path, output_path = sys.argv[1], sys.argv[2]

    # keep_trailing_newline so the rendered script ends the way the original
    # does; a missing final newline changes nothing functionally but makes
    # diffs against the template noisy.
    env = Environment(
        loader=FileSystemLoader("/"),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )
    rendered = env.get_template(template_path.lstrip("/")).render(**VARS)

    with open(output_path, "w") as handle:
        handle.write(rendered)


if __name__ == "__main__":
    main()
