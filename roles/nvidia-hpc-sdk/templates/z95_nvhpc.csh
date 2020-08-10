#!/usr/bin/env csh

setenv NVARCH `uname -s`_`uname -m`
setenv NVCOMPILERS {{ hpcsdk_install_dir }}
setenv MANPATH "$MANPATH":$NVCOMPILERS/$NVARCH/{{ hpcsdk_version_dir }}/compilers/man
set path = ($NVCOMPILERS/$NVARCH/{{ hpcsdk_version_dir }}/compilers/bin $path)
