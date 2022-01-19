#!/bin/bash
# This is a common set of libraries, configuration override, helper functions, and debug output
# This file should be sourced at the top of all scripts and primarily does 3 things
#  1. Will source the env.sh file to allow override variables be version controlled in ./config
#  2. Will print out some standard debug for each script, to ease debugging
#  3. Will provide a common set of libraries, directory names, etc.


# Determine the path to the configuration directory and verify it exists
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
DEEPOPS_CONFIG_DIR=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}
if [ ! -d "${DEEPOPS_CONFIG_DIR}" ]; then
  # Because this is a widely used script, we warn here instead of throwing an error
  echo "WARNING: Can't find configuration in ${DEEPOPS_CONFIG_DIR}"
  echo "WARNING: Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
else
  # Source the configuration environment variable overrides
  source ${DEEPOPS_CONFIG_DIR}/env.sh
fi

# Print out base debug
echo "Starting '${0}';  DeepOps version '${DEEPOPS_VERSION}'"
