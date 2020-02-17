#!/bin/bash
# -*- shell-script -*-
#  Lua based module management.
# -
if [ $(id -u) -ne 0 ] ; then
    export USER=${USER-${LOGNAME}}  # make sure $USER is set
    export LMOD_sys=`uname`

    LMOD_arch=`uname -m`
    if [ "x$LMOD_sys" = xAIX ]; then
      LMOD_arch=rs6k
    fi
    export LMOD_arch
    export LMOD_SETTARG_CMD=":"
    export LMOD_FULL_SETTARG_SUPPORT=no
    export LMOD_COLORIZE=yes
    export LMOD_PREPEND_BLOCK=normal
    export MODULEPATH_ROOT="{{ sm_module_root }}"
    export MODULEPATH="{{ sm_module_path }}"
    export MODULESHOME=/usr/share/lmod/lmod
    export BASH_ENV=$MODULESHOME/init/bash
    #
    # If MANPATH is empty, Lmod is adding a trailing ":" so that
    # the system MANPATH will be found
    #
    if [ -z "$MANPATH" ]; then
      export MANPATH=:
    fi
    export MANPATH=$(/usr/share/lmod/lmod/libexec/addto MANPATH /usr/share/lmod/lmod/share/man)
    . /usr/share/lmod/lmod/init/bash >/dev/null # Module Support
fi
