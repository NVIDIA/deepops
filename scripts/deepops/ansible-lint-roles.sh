#!/usr/bin/env bash

# Determine current directory and root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Allow optional passing of an exclude regex as an env var
ANSIBLE_LINT_EXCLUDE="${ANSIBLE_LINT_EXCLUDE:-galaxy}"

# Check for ansible-lint
if ! which ansible-lint 2>&1 >/dev/null; then
	echo "ansible-lint not found in PATH"
	exit 1
fi

# Use a var to set script failure so we check all roles
CHECK_FAILED=0;
failedRoles=();

# Lint each role
cd "${ROOT_DIR}/roles"
for r in $(find . -maxdepth 1 -mindepth 1 -type d | grep -v -E "${ANSIBLE_LINT_EXCLUDE}|galaxy"); do
	echo "==============================================================="
	echo "Linting ${r}"
	cd "${r}"
	if ! ansible-lint --parseable-severity; then
		CHECK_FAILED=1
		failedRoles+=("${r}")
	fi
	cd "${ROOT_DIR}/roles"
done

# Print summary of results
echo
echo "==============================================================="
echo "Failed roles:"
echo "  ${failedRoles[*]}"
echo "==============================================================="
exit ${CHECK_FAILED}
