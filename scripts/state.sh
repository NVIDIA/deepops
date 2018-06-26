#!/usr/bin/env bash

ansible dgx-servers -k -b -a "dpkg --get-selections | grep '\binstall$' | cut -f 1 > /shared/state/\$(hostname).log"
