#!/bin/sh
# -*- shell-script -*-
########################################################################
#  This is the system wide source file for setting up
#  modules:
#
########################################################################

if [ -z "$USER_IS_ROOT" ]; then

  if [ -z "$MODULEPATH_ROOT" ]; then
    export USER=${USER-${LOGNAME}}  # make sure $USER is set
    export LMOD_sys=`uname`

    LMOD_arch=`uname -m`
    if [ "x$LMOD_sys" = xAIX ]; then
      LMOD_arch=rs6k
    fi
    export LMOD_arch

    export MODULEPATH_ROOT="/shared/modules"
    export LMOD_SETTARG_CMD=":"
    export LMOD_FULL_SETTARG_SUPPORT=no
    export LMOD_COLORIZE=yes
    export LMOD_PREPEND_BLOCK=normal
#    export MODULEPATH=$(/usr/share/lmod/lmod/libexec/addto --append MODULEPATH $MODULEPATH_ROOT/$LMOD_sys $MODULEPATH_ROOT/Core)
#    export MODULEPATH=$(/usr/share/lmod/lmod/libexec/addto --append MODULEPATH /usr/share/lmod/lmod/modulefiles/Core)
    export MODULEPATH="{{ lmod_modulepath }}"
    export MODULESHOME=/usr/share/lmod/lmod

    export BASH_ENV=$MODULESHOME/init/bash

    #
    # If MANPATH is empty, Lmod is adding a trailing ":" so that
    # the system MANPATH will be found
    if [ -z "$MANPATH" ]; then
      export MANPATH=:
    fi
    export MANPATH=$(/usr/share/lmod/lmod/libexec/addto MANPATH /usr/share/lmod/lmod/share/man)
  fi

  . /usr/share/lmod/lmod/init/bash >/dev/null # Module Support

fi
