#!/usr/bin/env bash

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import shlex
import subprocess
import sys
import tempfile

import click
from cookiecutter.main import cookiecutter
from nvidia_deepops import Progress

host_path="/opt/deepops"

@click.command()
@click.option("--bootstrap")
def main(**config):
    subprocess.check_call(
        shlex.split("docker run --rm -ti -v {host_path}/config:/source/deepops/config --net=host deepops_deploy cp -r config.example {host_path}/config".format(host_path=host_path)),
        stdout=sys.stdout, stderr=sys.stderr
    )
    return 0

if __name__ == "__main__":
    main()
