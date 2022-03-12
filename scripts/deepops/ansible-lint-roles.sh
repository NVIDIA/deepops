#!/usr/bin/env bash

# Determine current directory and root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Check for ansible-lint
if ! which ansible-lint 2>&1 >/dev/null; then
	echo "ansible-lint not found in PATH"
	exit 1
fi

# Use a var to set script failure so we check all roles
CHECK_FAILED=0;

# Lint each role
cd "${ROOT_DIR}/roles"
for r in $(find . -maxdepth 1 -mindepth 1 -type d | grep -v galaxy); do
	echo "==============================================================="
	echo "Linting ${r}"
	cd "${r}"
	if ! ansible-lint ; then
		CHECK_FAILED=1
	fi
	cd "${ROOT_DIR}/roles"
done

exit ${CHECK_FAILED}
