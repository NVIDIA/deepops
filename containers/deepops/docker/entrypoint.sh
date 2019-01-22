#!/bin/bash

if [ -d /opt/deepops/ssh ]; then
  cp -r /opt/deepops/ssh ~/.ssh
  chown -R $USER:$USER ~/.ssh
fi

if [ ${#@} -eq 0 ]; then
    exec /bin/bash
else
    exec "$@"
fi
