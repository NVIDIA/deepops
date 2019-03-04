#!/usr/bin/env python3
import os
import re
import subprocess

try:
    nvcr_list = subprocess.run("nvidia-container-cli list -cuv", shell=True, check=True, stdout=subprocess.PIPE)
    nvcr_list = nvcr_list.stdout.decode("utf-8").rstrip().split('\n')

    # find nvidia-libraries path
    nvidia_lib_paths = [item for item in nvcr_list if '.so.' in item]
    nvidia_lib_names = ["/" + os.path.basename(item).split('.so.')[0] for item in nvidia_lib_paths]

    print("|".join(nvidia_lib_names))
except:
    pass
