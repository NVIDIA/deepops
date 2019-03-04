#!/usr/bin/env python3
import os
import re
import subprocess

try:
    nvcr_list = subprocess.run("nvidia-container-cli list -cuv", shell=True, check=True, stdout=subprocess.PIPE)
    nvcr_list = nvcr_list.stdout.decode("utf-8").rstrip().split('\n')
    nvidia_smi = [item for item in nvcr_list if 'nvidia-smi' in item][0]
    print(os.path.split(nvidia_smi)[0])
except:
    pass
