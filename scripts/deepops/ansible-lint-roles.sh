#!/usr/bin/env bash

# ansible-lint-roles.sh
# Runs ansible-lint against the DeepOps roles using the project .ansible-lint config.
#
# Roles can be excluded by setting the ANSIBLE_LINT_EXCLUDE variable to a
# regex matching the roles to skip (applied via exclude_paths in .ansible-lint)

# Determine current directory and root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Check for ansible-lint
if ! command -v ansible-lint >/dev/null 2>&1; then
	echo "ansible-lint not found in PATH"
	exit 1
fi

cd "${ROOT_DIR}" || exit 1

echo "==============================================================="
echo "Running ansible-lint with project config (.ansible-lint)"
echo "ansible-lint version: $(ansible-lint --version 2>&1 | head -1)"
echo "==============================================================="

# Run ansible-lint from project root — it picks up .ansible-lint config
# which handles exclude_paths, skip_list, and profile settings
ansible-lint -f pep8 roles/
exit_code=$?

echo
echo "==============================================================="
if [ $exit_code -eq 0 ]; then
	echo "Lint: PASSED"
else
	echo "Lint: FAILED (exit code ${exit_code})"
fi
echo "==============================================================="
exit $exit_code
