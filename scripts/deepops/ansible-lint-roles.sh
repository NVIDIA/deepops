#!/usr/bin/env bash

# ansible-lint-roles.sh
# Runs ansible-lint against each of the subdirectories in roles/
#
# Roles can be excluded by setting the ANSIBLE_LINT_EXCLUDE variable to a
# regex matching the roles to skip

# Determine current directory and root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Allow optional passing of an exclude regex as an env var
ANSIBLE_LINT_EXCLUDE="${ANSIBLE_LINT_EXCLUDE:-galaxy}"

# Check for ansible-lint
if ! command -v ansible-lint >/dev/null 2>&1; then
	echo "ansible-lint not found in PATH"
	exit 1
fi

# Use a var to set script failure so we check all roles
CHECK_FAILED=0;
failedRoles=();

# Lint each role
cd "${ROOT_DIR}/roles" || exit 1
for r in $(find . -maxdepth 1 -mindepth 1 -type d | grep -v -E "${ANSIBLE_LINT_EXCLUDE}|galaxy"); do
	echo "==============================================================="
	echo "Linting ${r}"
	cd "${r}" || exit 1
	if ! ansible-lint --parseable-severity; then
		CHECK_FAILED=1
		failedRoles+=("${r}")
	fi
	cd "${ROOT_DIR}/roles" || exit 1
done

# Print summary of results
echo
echo "==============================================================="
echo "Failed roles:"
echo "  ${failedRoles[*]}"
echo "Excluded role directories:"
echo "  $(find . -maxdepth 1 -mindepth 1 -type d | grep -E "${ANSIBLE_LINT_EXCLUDE}|galaxy" | xargs)"
echo "==============================================================="
exit ${CHECK_FAILED}
