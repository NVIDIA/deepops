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

SCOPES = ("job", "user")


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: render.py <template-path> <output-path> [job|user]")

    template_path, output_path = sys.argv[1], sys.argv[2]
    # slurm_epilog_cleanup_scope. "job" is the role default.
    scope = sys.argv[3] if len(sys.argv) == 4 else "job"
    if scope not in SCOPES:
        sys.exit("scope must be one of: " + ", ".join(SCOPES))

    # keep_trailing_newline so the rendered script ends the way the original
    # does; a missing final newline changes nothing functionally but makes
    # diffs against the template noisy.
    # autoescape stays off, and is written out rather than left to the default
    # so the reason sits where the scanner alert lands (CodeQL
    # py/jinja2/autoescape-false, CWE-79).
    #
    # The output here is a shell script written to a local file for `bash -n`
    # and for the harness to execute. It is never a web response and never
    # reaches a browser. HTML escaping would not protect it; it would corrupt
    # it -- `&&` becomes `&amp;&amp;`, `>"$victims"` becomes `&gt;&#34;...`,
    # and the rendered script stops being the one a deployment runs, which is
    # the whole point of rendering instead of testing a trimmed copy.
    #
    # The values substituted are the fixed fixture constants in VARS above, not
    # anything read from the environment or from a caller.
    env = Environment(
        loader=FileSystemLoader("/"),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        # Ansible's template module sets trim_blocks, so a block tag on a line
        # of its own leaves no blank line behind. Match it, or the rendered
        # scripts here differ from the deployed ones.
        trim_blocks=True,
        autoescape=False,
    )
    rendered = env.get_template(template_path.lstrip("/")).render(
        slurm_epilog_cleanup_scope=scope, **VARS
    )

    with open(output_path, "w") as handle:
        handle.write(rendered)


if __name__ == "__main__":
    main()
